/**
 * Client half of the SessionCap pattern (see move/ore_forge/sources/session.move
 * and docs §7 of the sui reference).
 *
 * The browser holds an ephemeral Ed25519 keypair in localStorage. The real
 * wallet signs ONE transaction that mints a SessionCap for the ephemeral
 * address and tops it up with a small gas allowance. Every mine/smelt after
 * that is signed silently by the ephemeral key — no wallet popups.
 */
import { bcs } from '@mysten/sui/bcs';
import type { SuiGrpcClient } from '@mysten/sui/grpc';
import { Ed25519Keypair } from '@mysten/sui/keypairs/ed25519';
import { Transaction } from '@mysten/sui/transactions';

import {
  PACKAGE_ID,
  SESSION_ACTIONS,
  SESSION_GAS_MIST,
  SESSION_TTL_MS,
  WORLD_ID,
} from './config';

const KEY_STORAGE = 'ore-forge:session-key';
const SESSION_STORAGE = 'ore-forge:session';

export interface SessionInfo {
  capId: string;
  /** The real wallet this session acts for. */
  player: string;
  sessionAddress: string;
  expiresAtMs: number;
  actionsLeft: number;
}

const SessionMintedBcs = bcs.struct('SessionMinted', {
  capId: bcs.Address,
  player: bcs.Address,
  sessionAddress: bcs.Address,
  expiresAtMs: bcs.u64(),
  actions: bcs.u64(),
});

export function loadEphemeralKeypair(): Ed25519Keypair {
  const stored = localStorage.getItem(KEY_STORAGE);
  if (stored) return Ed25519Keypair.fromSecretKey(stored);
  const keypair = Ed25519Keypair.generate();
  localStorage.setItem(KEY_STORAGE, keypair.getSecretKey());
  return keypair;
}

/**
 * On-chain "forever" is the u64::MAX sentinel (~1.8e19). Anything past
 * MAX_SAFE_INTEGER can only be that sentinel, so this test is exact enough.
 */
export function isUnlimited(value: number): boolean {
  return value >= Number.MAX_SAFE_INTEGER;
}

export function loadStoredSession(player: string): SessionInfo | null {
  const raw = localStorage.getItem(SESSION_STORAGE);
  if (!raw) return null;
  try {
    const session = JSON.parse(raw) as SessionInfo;
    const valid =
      session.player === player &&
      session.expiresAtMs > Date.now() &&
      session.actionsLeft > 0;
    return valid ? session : null;
  } catch {
    return null;
  }
}

export function saveSession(session: SessionInfo) {
  localStorage.setItem(SESSION_STORAGE, JSON.stringify(session));
}

export function clearStoredSession() {
  localStorage.removeItem(SESSION_STORAGE);
}

/**
 * THE one wallet-signed transaction of the whole game: optionally create the
 * player, mint a SessionCap to the ephemeral address, and split off a gas
 * allowance so the ephemeral key can pay for its own transactions. Everything
 * after this — mining, smelting, smithing NFTs — is signed silently.
 * (Sponsored transactions would replace the allowance in a production build.)
 */
export function buildStartSessionTx(
  sessionAddress: string,
  createPlayer: boolean,
): Transaction {
  const tx = new Transaction();
  if (createPlayer) {
    tx.moveCall({
      target: `${PACKAGE_ID}::forge::create_player`,
      arguments: [tx.object(WORLD_ID)],
    });
  }
  tx.moveCall({
    target: `${PACKAGE_ID}::session::mint`,
    arguments: [
      tx.pure.address(sessionAddress),
      tx.pure.u64(SESSION_TTL_MS),
      tx.pure.u64(SESSION_ACTIONS),
      tx.object.clock(),
    ],
  });
  const [allowance] = tx.splitCoins(tx.gas, [tx.pure.u64(SESSION_GAS_MIST)]);
  tx.transferObjects([allowance], tx.pure.address(sessionAddress));
  return tx;
}

/** Parse the SessionMinted event out of a confirmed transaction's events. */
export function parseSessionMinted(
  events: { eventType: string; bcs: Uint8Array }[] | undefined,
): SessionInfo | null {
  const event = events?.find((e) => e.eventType.endsWith('::session::SessionMinted'));
  if (!event) return null;
  const parsed = SessionMintedBcs.parse(event.bcs);
  return {
    capId: parsed.capId,
    player: parsed.player,
    sessionAddress: parsed.sessionAddress,
    expiresAtMs: Number(parsed.expiresAtMs),
    actionsLeft: Number(parsed.actions),
  };
}

/**
 * Sign and execute with the ephemeral key, then wait for indexing.
 * Returns the confirmed transaction's events.
 *
 * Calls must be sequential: the cap and the gas coin are owned objects, so
 * concurrent submissions would equivocate ("objects reserved for another
 * transaction").
 */
export async function executeAsSession(
  client: SuiGrpcClient,
  keypair: Ed25519Keypair,
  tx: Transaction,
): Promise<{ eventType: string; bcs: Uint8Array }[]> {
  const result = await client.core.signAndExecuteTransaction({
    transaction: tx,
    signer: keypair,
    include: { events: true },
  });
  if (result.FailedTransaction) {
    throw new Error(
      `Transaction failed: ${result.FailedTransaction.status.error?.message ?? 'unknown'}`,
    );
  }
  await client.core.waitForTransaction({ digest: result.Transaction!.digest });
  return result.Transaction!.events ?? [];
}

/**
 * Revoke the cap and sweep the remaining gas allowance back to the player —
 * one PTB signed by the ephemeral key.
 */
export function buildEndSessionTx(session: SessionInfo): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::session::revoke`,
    arguments: [tx.object(session.capId)],
  });
  tx.transferObjects([tx.gas], tx.pure.address(session.player));
  return tx;
}
