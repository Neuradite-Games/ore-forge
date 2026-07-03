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

The point of the exercise: mining and smelting run **without wallet popups** via
the hand-rolled SessionCap pattern — one wallet signature mints a session
capability for an ephemeral browser keypair, which then signs every click
silently.

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
  transferred. Defense layers: Clock expiry (max 8 h), decrementing action
  budget, and a **tier split**: the cap only gates non-extractive verbs
  (`mine`, `smelt`). Smithing mints tradable assets, so it demands the real
  wallet's signature. No revocation registry (would put a shared object in every
  gameplay tx) — short expiry + owner-side `revoke` cover the prototype.
- **`mine` is a non-public `entry` fun** — required by the framework for
  functions consuming `Random` (blocks test-and-abort bias). Everything else is
  `public` for composability; smithing returns the object and lets the PTB
  decide where it goes.
- **Session gas**: the session-start PTB splits off 0.05 SUI to the ephemeral
  address so it can pay for its own transactions. Ending a session revokes the
  cap and sweeps the remainder back. (Production path: sponsored transactions /
  Enoki instead of an allowance.)
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

   Flow to verify: connect wallet → **Create player** (wallet signs) → **Start
   session** (wallet signs once; 0.05 SUI moves to the session key) → click ore
   nodes / furnace (NO popups — this is the whole point) → smith a sword
   (wallet signs) → check the Weapon object appears in your wallet → **End
   session** (gas swept back).

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
