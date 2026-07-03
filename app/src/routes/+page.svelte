<script lang="ts">
  import { onMount } from 'svelte';
  import { ConnectButton } from '@builders-of-stuff/svelte-sui-wallet-adapter';
  import type { Transaction } from '@mysten/sui/transactions';

  import PhaserContainer from '$lib/game/phaser-container.svelte';
  import { gameEvents } from '$lib/game/event-bus';
  import { addLog, gameState } from '$lib/state/game-state.svelte';
  import {
    ARMOUR_INGOT_COST,
    isConfigured,
    NETWORK,
    SESSION_ACTIONS,
    SMELT_ORE_COST,
    WEAPON_INGOT_COST,
  } from '$lib/sui/config';
  import {
    buildMineTx,
    buildSmeltTx,
    buildSmithTx,
    fetchEquipment,
    fetchPlayerStats,
    IngotSmeltedBcs,
    OreMinedBcs,
  } from '$lib/sui/forge-client';
  import {
    buildEndSessionTx,
    buildStartSessionTx,
    clearStoredSession,
    executeAsSession,
    isUnlimited,
    loadEphemeralKeypair,
    loadStoredSession,
    parseSessionMinted,
    saveSession,
  } from '$lib/sui/session';
  import { walletAdapter } from '$lib/sui/wallet';

  const address = $derived(walletAdapter.currentAccount?.address ?? null);
  const client = walletAdapter.suiClient;

  let loadedFor: string | null = $state(null);

  $effect(() => {
    if (address && address !== loadedFor) {
      loadedFor = address;
      void refresh(address);
    } else if (!address && loadedFor) {
      loadedFor = null;
      gameState.hasPlayer = false;
      gameState.session = null;
    }
  });

  async function refresh(player: string) {
    if (!isConfigured) return;
    const stats = await fetchPlayerStats(client, player);
    gameState.hasPlayer = stats !== null;
    if (stats) {
      gameState.ore = stats.ore;
      gameState.ingots = stats.ingots;
      gameState.weaponsSmithed = stats.weaponsSmithed;
      gameState.armourSmithed = stats.armourSmithed;
      gameState.equipment = await fetchEquipment(client, player);
    }
    gameState.session = loadStoredSession(player);
  }

  /** Wallet-signed path: execute, check status, wait, return events. */
  async function signWithWallet(tx: Transaction) {
    const result = await walletAdapter.signAndExecuteTransaction({
      transaction: tx,
    });
    if (result.$kind === 'FailedTransaction') {
      throw new Error('Transaction failed');
    }
    const confirmed = await walletAdapter.waitForTransaction({
      digest: result.Transaction.digest,
      include: { events: true },
    });
    return confirmed.Transaction?.events ?? [];
  }

  function guard(): boolean {
    if (!isConfigured) {
      addLog('Contracts not configured — see PROJECT.md');
      return false;
    }
    if (!address) {
      addLog('Connect your wallet first');
      return false;
    }
    if (gameState.pending) return false; // one tx at a time (owned objects)
    return true;
  }

  /**
   * The only wallet popup in the game: creates the player (if needed), mints
   * the SessionCap, and funds the ephemeral key — one signature.
   */
  async function startSession() {
    if (!guard()) return;
    gameState.pending = 'start-session';
    try {
      const keypair = loadEphemeralKeypair();
      const events = await signWithWallet(
        buildStartSessionTx(keypair.toSuiAddress(), !gameState.hasPlayer),
      );
      const session = parseSessionMinted(events);
      if (!session) throw new Error('SessionMinted event not found');
      saveSession(session);
      gameState.hasPlayer = true;
      gameState.session = session;
      const budget = isUnlimited(session.actionsLeft)
        ? 'unlimited actions'
        : `${session.actionsLeft} actions`;
      addLog(`Session started: ${budget}, no more popups until you end it ⚡`);
    } catch (error) {
      addLog(`Start session failed: ${(error as Error).message}`);
    } finally {
      gameState.pending = null;
    }
  }

  async function endSession() {
    if (!gameState.session || gameState.pending) return;
    gameState.pending = 'end-session';
    try {
      // Signed by the ephemeral key: revoke the cap, sweep gas back.
      await executeAsSession(
        client,
        loadEphemeralKeypair(),
        buildEndSessionTx($state.snapshot(gameState.session)),
      );
      addLog('Session revoked, gas allowance returned');
    } catch (error) {
      addLog(`Revoke failed (session may have expired): ${(error as Error).message}`);
    } finally {
      clearStoredSession();
      gameState.session = null;
      gameState.pending = null;
    }
  }

  function sessionValid(): boolean {
    const session = gameState.session;
    if (!session) {
      addLog('Start a mining session first');
      return false;
    }
    if (session.expiresAtMs <= Date.now() || session.actionsLeft <= 0) {
      addLog('Session expired or exhausted — start a new one');
      clearStoredSession();
      gameState.session = null;
      return false;
    }
    return true;
  }

  function spendSessionAction() {
    if (!gameState.session || isUnlimited(gameState.session.actionsLeft)) return;
    gameState.session.actionsLeft -= 1;
    saveSession($state.snapshot(gameState.session));
  }

  async function mine(nodeId: number) {
    if (!guard() || !sessionValid()) {
      gameEvents.emit('mine-failed', { nodeId });
      return;
    }
    gameState.pending = 'mine';
    gameEvents.emit('busy', { busy: true });
    try {
      const events = await executeAsSession(
        client,
        loadEphemeralKeypair(),
        buildMineTx(gameState.session!.capId),
      );
      const mined = events.find((e) => e.eventType.endsWith('::forge::OreMined'));
      if (!mined) throw new Error('OreMined event not found');
      const parsed = OreMinedBcs.parse(mined.bcs);
      gameState.ore = Number(parsed.oreTotal);
      spendSessionAction();
      gameEvents.emit('mine-result', { nodeId, amount: Number(parsed.amount) });
      addLog(`Mined ${parsed.amount} ore`);
    } catch (error) {
      gameEvents.emit('mine-failed', { nodeId });
      addLog(`Mine failed: ${(error as Error).message}`);
    } finally {
      gameState.pending = null;
      gameEvents.emit('busy', { busy: false });
    }
  }

  async function smelt() {
    if (!guard() || !sessionValid()) {
      gameEvents.emit('smelt-failed');
      return;
    }
    if (gameState.ore < SMELT_ORE_COST) {
      addLog(`Need ${SMELT_ORE_COST} ore to smelt an ingot`);
      gameEvents.emit('smelt-failed');
      return;
    }
    gameState.pending = 'smelt';
    gameEvents.emit('busy', { busy: true });
    try {
      const events = await executeAsSession(
        client,
        loadEphemeralKeypair(),
        buildSmeltTx(gameState.session!.capId),
      );
      const smelted = events.find((e) => e.eventType.endsWith('::forge::IngotSmelted'));
      if (!smelted) throw new Error('IngotSmelted event not found');
      const parsed = IngotSmeltedBcs.parse(smelted.bcs);
      gameState.ore -= Number(parsed.oreSpent);
      gameState.ingots = Number(parsed.ingotTotal);
      spendSessionAction();
      gameEvents.emit('smelt-result');
      addLog('Smelted 1 ingot');
    } catch (error) {
      gameEvents.emit('smelt-failed');
      addLog(`Smelt failed: ${(error as Error).message}`);
    } finally {
      gameState.pending = null;
      gameEvents.emit('busy', { busy: false });
    }
  }

  async function smith(kind: 'weapon' | 'armour') {
    if (!guard() || !sessionValid()) {
      gameEvents.emit('smith-failed', { kind });
      return;
    }
    const cost = kind === 'weapon' ? WEAPON_INGOT_COST : ARMOUR_INGOT_COST;
    if (gameState.ingots < cost) {
      addLog(`Need ${cost} ingots to smith a ${kind}`);
      gameEvents.emit('smith-failed', { kind });
      return;
    }
    gameState.pending = `smith-${kind}`;
    gameEvents.emit('busy', { busy: true });
    try {
      // Session-signed mint: Move delivers the NFT to the real wallet.
      await executeAsSession(
        client,
        loadEphemeralKeypair(),
        buildSmithTx(kind, gameState.session!.capId),
      );
      spendSessionAction();
      gameState.ingots -= cost;
      if (kind === 'weapon') gameState.weaponsSmithed += 1;
      else gameState.armourSmithed += 1;
      gameState.equipment = await fetchEquipment(client, address!);
      gameEvents.emit('smith-result', { kind });
      addLog(`Smithed a ${kind} ⚒`);
    } catch (error) {
      gameEvents.emit('smith-failed', { kind });
      addLog(`Smith failed: ${(error as Error).message}`);
    } finally {
      gameState.pending = null;
      gameEvents.emit('busy', { busy: false });
    }
  }

  onMount(() => {
    const unsubscribers = [
      gameEvents.on('mine', ({ nodeId }) => void mine(nodeId)),
      gameEvents.on('smelt', () => void smelt()),
      gameEvents.on('smith-weapon', () => void smith('weapon')),
      gameEvents.on('smith-armour', () => void smith('armour')),
    ];
    return () => unsubscribers.forEach((unsubscribe) => unsubscribe());
  });

  function formatExpiry(expiresAtMs: number): string {
    if (isUnlimited(expiresAtMs)) return 'until you end it';
    const minutes = Math.max(0, Math.round((expiresAtMs - Date.now()) / 60_000));
    return `${minutes} min left`;
  }

  function formatActions(actionsLeft: number): string {
    return isUnlimited(actionsLeft) ? '∞' : `${actionsLeft}/${SESSION_ACTIONS}`;
  }
</script>

<svelte:head>
  <title>Ore Forge</title>
</svelte:head>

<div class="page">
  <header>
    <h1>⛏ Ore Forge</h1>
    <span class="network">{NETWORK}</span>
    <div class="spacer"></div>
    <ConnectButton {walletAdapter} />
  </header>

  {#if !isConfigured}
    <div class="banner">
      Contracts not configured. Deploy the Move package, then set
      <code>PUBLIC_PACKAGE_ID</code> and <code>PUBLIC_WORLD_ID</code> in
      <code>app/.env</code> — see <code>PROJECT.md</code> for instructions.
    </div>
  {/if}

  <main>
    <div class="canvas-column">
      <PhaserContainer />
      {#if gameState.pending}
        <p class="pending">⏳ {gameState.pending} transaction in flight…</p>
      {/if}
    </div>

    <aside>
      {#if !address}
        <section>
          <h2>Welcome</h2>
          <p>Connect a wallet to start mining on {NETWORK}.</p>
        </section>
      {:else}
        <section>
          <h2>Session</h2>
          {#if gameState.session}
            <p class="session-live">
              ⚡ live — {formatActions(gameState.session.actionsLeft)} actions,
              {formatExpiry(gameState.session.expiresAtMs)}
            </p>
            <button onclick={endSession} disabled={gameState.pending !== null}>
              End session
            </button>
          {:else}
            <p>
              Sign <strong>once</strong> to start a session — then everything (mining, smelting,
              smithing NFTs) runs with zero popups, forever, until you end it. NFTs always
              land in your real wallet.
            </p>
            <button onclick={startSession} disabled={gameState.pending !== null}>
              Start session
            </button>
          {/if}
        </section>

        <section>
          <h2>Inventory</h2>
          <ul class="inventory">
            <li>🪨 Ore <strong>{gameState.ore}</strong></li>
            <li>🧱 Ingots <strong>{gameState.ingots}</strong></li>
            <li>⚔️ Weapons <strong>{gameState.weaponsSmithed}</strong></li>
            <li>🛡️ Armour <strong>{gameState.armourSmithed}</strong></li>
          </ul>
          {#if gameState.equipment.length > 0}
            <details>
              <summary>{gameState.equipment.length} owned item(s)</summary>
              <ul class="equipment">
                {#each gameState.equipment as item (item.objectId)}
                  <li>
                    {item.kind === 'weapon' ? '⚔️' : '🛡️'}
                    <code>{item.objectId.slice(0, 10)}…</code>
                  </li>
                {/each}
              </ul>
            </details>
          {/if}
        </section>
      {/if}

      <section class="log">
        <h2>Log</h2>
        <ul>
          {#each gameState.log as entry, index (index)}
            <li><span>{entry.time}</span> {entry.message}</li>
          {/each}
        </ul>
      </section>
    </aside>
  </main>
</div>

<style>
  :global(body) {
    margin: 0;
    background: #0e0b09;
    color: #e8e0d0;
    font-family:
      system-ui,
      -apple-system,
      sans-serif;
  }

  .page {
    max-width: 1320px;
    margin: 0 auto;
    padding: 1rem 1.5rem 3rem;
  }

  header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding-block: 0.5rem 1rem;
  }

  h1 {
    font-size: 1.5rem;
    margin: 0;
  }

  .network {
    background: #2d3446;
    border-radius: 999px;
    padding: 0.15rem 0.6rem;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .spacer {
    flex: 1;
  }

  .banner {
    background: #4a3428;
    border: 1px solid #8a5c3c;
    border-radius: 8px;
    padding: 0.75rem 1rem;
    margin-bottom: 1rem;
    font-size: 0.9rem;
  }

  main {
    display: flex;
    gap: 1.25rem;
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .canvas-column {
    flex: 2 1 560px;
    min-width: 320px;
  }

  .pending {
    color: #ffd479;
    font-size: 0.85rem;
  }

  aside {
    flex: 1 1 280px;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  section {
    background: #1a1611;
    border: 1px solid #2e2820;
    border-radius: 8px;
    padding: 0.9rem 1rem;
  }

  h2 {
    margin: 0 0 0.5rem;
    font-size: 0.85rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #9a917e;
  }

  section p {
    margin: 0.25rem 0 0.75rem;
    font-size: 0.9rem;
    line-height: 1.45;
  }

  .session-live {
    color: #9be07d;
  }

  button {
    background: #4da2ff;
    color: #0e0b09;
    border: none;
    border-radius: 6px;
    padding: 0.5rem 1rem;
    font-weight: 600;
    cursor: pointer;
  }

  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .inventory li {
    display: flex;
    justify-content: space-between;
    padding-block: 0.2rem;
    font-size: 0.95rem;
  }

  .equipment li {
    font-size: 0.85rem;
    padding-block: 0.15rem;
  }

  .log ul {
    max-height: 220px;
    overflow-y: auto;
    font-size: 0.8rem;
  }

  .log li {
    padding-block: 0.2rem;
    border-bottom: 1px solid #2e2820;
  }

  .log li span {
    color: #9a917e;
    margin-right: 0.4rem;
  }
</style>
