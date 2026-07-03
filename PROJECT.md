# Ore Forge — Project Notes

_Last updated: 2026-07-03_

A simple on-chain ore mining game on Sui, built to exercise the autonomous-games
and session-key patterns from `games/docs/sui-reference.md` (§6 Autonomous games,
§7 Session keys / SessionCap).

## Overview

One Phaser canvas, three areas:

1. **Ore field** — click ore nodes to mine. Each click is a Sui transaction that
   yields 1–3 ore (on-chain randomness via `Random` at `0x8`).
2. **Furnace** — click to smelt 3 ore into 1 ingot.
3. **Anvil** — smith ingots into gear: a sword costs 2 ingots, armour costs 3.
   Each smith mints a tradable `key, store` object (`Weapon` / `Armour`) sent to
   your wallet.

**The point of the exercise is session keys**: you sign with your wallet
exactly ONCE, and that signature covers everything — mining, smelting, and
minting Weapon/Armour NFTs — **forever, until you manually end the session**.
The one signed transaction creates your player (if needed), mints a
`SessionCap` for an ephemeral browser keypair, and funds it; every click after
that is signed silently by the ephemeral key.

### How assets reach the real wallet without extra signatures

The signer of a Sui transaction and the owner of the objects it creates are
independent — ownership is data on the object, decided by what the Move code
does, not "sender keeps it". Concretely:

- Ore/ingots are counters in a dynamic field on the shared `World` keyed by
  `cap.player` (the real wallet). Game functions never consult `ctx.sender()`
  (which would be the ephemeral key).
- Smithing goes through `smith_*_and_keep`, which does
  `transfer::public_transfer(item, cap.player())` **inside Move** — NFT
  delivery to the real wallet is an on-chain guarantee in the same
  session-signed transaction; no client code (or attacker holding the
  ephemeral key) can redirect it.
- The ephemeral address only ever holds the `SessionCap` and its gas coin.

## Stack

- **Contracts**: Move 2024 (`move/ore_forge/`), two modules:
  - `forge.move` — shared `World`, player state, mine/smelt/smith
  - `session.move` — `SessionCap` (hand-rolled session keys)
- **Frontend**: SvelteKit (Svelte 5 runes) + Phaser 4 (`app/`), pnpm
- **Wallet**: `@builders-of-stuff/svelte-sui-wallet-adapter` v3
- **SDK**: `@mysten/sui` v2 (gRPC client via the adapter)

## Architecture decisions (and why)

- **Player state lives in dynamic fields on the shared `World`** (keyed by
  `PlayerKey(address)`), NOT in an address-owned object. Reason: the session
  (ephemeral) key signs gameplay transactions, and an owned object could only be
  passed by transactions the *real wallet* signs. Reachability from shared state
  is what makes session play possible.
- **SessionCap is `key`-only** — can't be wrapped, traded, or generically
  transferred. Supports Clock expiry and an action budget, but **`ttl_ms = 0`
  / `actions = 0` mean forever/unlimited** (encoded as `u64::MAX` on-chain),
  and the app mints forever-sessions — per the project goal, a session lives
  until you hit End session (`revoke`). No revocation registry (would put a
  shared object in every gameplay tx). Stolen-localStorage tradeoff accepted
  knowingly: a thief could spend your ore/ingots and gas until you revoke,
  but can never extract NFTs (they always land in `cap.player()`).
- **ALL verbs are session-gated, including NFT minting.** The reference doc's
  production guidance is a "tier split" (session key gates only non-extractive
  verbs; minting demands the real wallet), but the explicit goal of this
  prototype is to test sign-once-then-mint-freely, so smithing takes the cap
  too. Mitigation kept: minted NFTs are always delivered to `cap.player()` —
  the real wallet — never to the ephemeral signer, so a stolen session key can
  spend your ingots but cannot steal the resulting gear. Revisit the tier split
  if this ever grows past a prototype.
- **`mine` is a non-public `entry` fun** — required by the framework for
  functions consuming `Random` (blocks test-and-abort bias). Everything else is
  `public` for composability; smithing returns the object and lets the PTB
  decide where it goes.
- **One signature total**: the session-start PTB chains `create_player` (first
  time only) + `session::mint` + a 0.1 SUI gas allowance to the ephemeral
  address. Ending a session revokes the cap and sweeps the remainder back.
  If a long-lived session runs dry, send more SUI to the session address (or
  end/restart). (Production path: sponsored transactions / Enoki instead of
  an allowance.)
- **Frontend reads events from BCS** (`event.bcs` parsed with `bcs.struct`),
  not `event.json` — the JSON shape varies across API implementations.
- **Upgrade hygiene**: `World.version` gate + `AdminCap` + `migrate()` from day
  one; frontend config carries `PACKAGE_ID` (latest, for moveCalls) and
  `ORIGINAL_PACKAGE_ID` (for type/event queries) separately because struct types
  anchor to the original package id.
- **One transaction at a time** in the client: the cap and gas coin are owned
  objects — concurrent submissions would equivocate ("objects reserved for
  another transaction"). Clicks while a tx is in flight are ignored.
- Naming note: the middle area is called **furnace/smelt** in code (ores →
  ingots) and the third area **anvil/smith** (ingots → gear), matching the
  usual smelting-vs-smithing split.

## Milestones

- [x] **M1 — Contracts**: `forge.move` + `session.move`, 7 unit tests green
      (`sui move test --build-env testnet`)
- [x] **M2 — Frontend skeleton**: SvelteKit + Phaser canvas with the three
      areas, wallet connect, HUD (inventory, session panel, log)
- [x] **M3 — Chain wiring**: create player, start/end session, mine, smelt,
      smith — all built and type-checked (`pnpm check`, `pnpm build` green)
- [ ] **M4 — Deploy & end-to-end test on testnet** ← YOU ARE HERE (manual step,
      instructions below)
- [ ] **M5 — Polish (optional)**: sounds, better ore-node art, mining latency
      feel (optimistic clicks with rollback), session auto-renew prompt
- [ ] **M6 — Later ideas**: sponsored txs (drop the gas allowance), Object
      Display for Weapon/Armour so wallets render them, Kiosk listing, ore
      types/tiers, leaderboard via custom indexer

## Progress log

- **2026-07-03** — Repo created. Contracts written and unit-tested (7/7 pass).
  Full frontend written and building. Not yet deployed to any network; app
  shows a "contracts not configured" banner until `.env` is filled in.
- **2026-07-03 (later)** — Reworked per feedback: session keys are the star.
  Dropped the wallet-signs-smithing tier split — the SessionCap now gates ALL
  verbs including NFT minting (NFTs still delivered to the real wallet), and
  player creation is folded into the session-start PTB. Net result: exactly one
  wallet popup per session. Tests updated, still 7/7.
- **2026-07-03 (later still)** — Forever sessions: `ttl_ms = 0` / `actions = 0`
  now mean never-expires/unlimited (u64::MAX on-chain); the app mints
  forever-sessions that live until End session. NFT delivery moved fully
  on-chain (frontend calls `smith_*_and_keep`, which transfers to
  `cap.player()` in Move). Gas allowance bumped to 0.1 SUI. Tests 8/8.

## Deploy instructions (manual — do this to reach M4)

Contracts are NOT deployed yet. The frontend is coded as if they were; it just
needs the ids.

1. Publish (CLI ≥ 1.63; check `sui client active-env` first):

   ```bash
   cd move/ore_forge
   sui client switch --env testnet
   sui client faucet   # if you need gas — or use faucet.sui.io
   sui move test --build-env testnet   # sanity: 7 tests green
   sui client publish
   ```

2. From the publish output, record:
   - **Package ID** (`Published Objects → PackageID`)
   - **World object ID** — the created shared object of type
     `<PKG>::forge::World`
   - The `AdminCap` and `UpgradeCap` land in your wallet; keep them safe
     (`Published.toml` is written automatically — commit it).

3. Configure the app:

   ```bash
   cd ../../app
   cp .env.example .env
   # set PUBLIC_PACKAGE_ID=<package id>
   # set PUBLIC_WORLD_ID=<world object id>
   # leave PUBLIC_ORIGINAL_PACKAGE_ID empty until the first package upgrade
   ```

4. Run and play:

   ```bash
   pnpm install
   pnpm dev
   ```

   Flow to verify: connect wallet → **Start session** (the ONLY wallet popup:
   creates player + mints a forever-cap + funds the session key with 0.1 SUI)
   → click ore nodes, furnace, and smith buttons — all with zero popups —
   → check the Weapon/Armour objects appear in your REAL wallet (not the
   session address) → reload the page: the session persists from localStorage
   → **End session** (cap revoked, leftover gas swept back).

5. Update this file: tick M4, note the package/world ids and any issues in the
   progress log.

### After a package upgrade (future)

`sui client upgrade --upgrade-capability <CAP_ID>`, then set
`PUBLIC_PACKAGE_ID` to the NEW id and `PUBLIC_ORIGINAL_PACKAGE_ID` to the FIRST
published id (type queries stay anchored there). If you bump `VERSION` in
`forge.move`, call `migrate(AdminCap, World)` right after upgrading.

## Development commands

| What | Where | Command |
|---|---|---|
| Move tests | `move/ore_forge/` | `sui move test --build-env testnet` |
| Move build | `move/ore_forge/` | `sui move build --build-env testnet` |
| Dev server | `app/` | `pnpm dev` |
| Type check | `app/` | `pnpm check` |
| Prod build | `app/` | `pnpm build` |

## Known gaps / honest notes

- **Untested against a live network.** Unit tests and type checks pass, but the
  full client flow (event BCS parsing, dynamic-field reads, gas allowance
  sizing) hasn't run against testnet yet — expect to shake out 1–2 small issues
  at M4.
- Mining latency = one consensus round-trip per click (~1–3 s on testnet); the
  UI blocks clicks while a tx is in flight. This is the known latency floor of
  on-chain play (reference doc §7b), not a bug.
- `adapter-auto` warns at build time that no deploy platform is detected —
  harmless for local dev; pick an adapter (or Walrus Sites + `adapter-static`)
  when hosting matters.
- The ephemeral key sits in `localStorage` — acceptable for its scoped, expiring
  authority (that's the design), but don't raise the gas allowance carelessly.
