# Ore Forge — Project Notes

_Last updated: 2026-07-03_

A simple on-chain ore mining game on Sui, built to exercise the autonomous-games
and session-key patterns from `games/docs/sui-reference.md` (§6 Autonomous games,
§7 Session keys / SessionCap).

## Overview

One Phaser canvas, three areas:

1. **Ore field** — click ore nodes to mine. Each click is a Sui transaction that
   mints 1–3 **ORE coins** (on-chain randomness via `Random` at `0x8`).
2. **Furnace** — click to burn 3 ORE and mint 1 **INGOT coin**.
3. **Anvil** — smith ingots into gear: a sword costs 2 ingots, armour costs 3.
   Each smith burns the INGOTs and mints a **Weapon/Armour NFT** with Object
   Display (name + image) straight into your real wallet.

**Everything is a real wallet asset — there is no world/registry object.**
ORE and INGOT are genuine `Coin` currencies (icon, symbol, metadata; they show
up in any Sui wallet like any other token). Gear is genuine `key, store` NFTs
that wallets/explorers render with images. The only shared object is a minimal
`Forge` holding the two treasury caps (mint/burn authority).

**The point of the exercise is session keys**: you sign with your wallet
exactly ONCE, and that signature covers everything — mining, smelting, and
minting NFTs — **forever, until you manually end the session**. Every click
after the first signature is signed silently by an ephemeral browser keypair.

### The pouch: how coins + session keys coexist

Spending an owned coin requires its owner's signature — that's Sui's object
model, not a design choice. If mined ORE went straight to your main wallet,
every smelt would need a wallet popup again. So:

- **Mine** mints ORE to the **session address** — the "pouch". These are real
  coins in a real wallet; the session key can spend them silently.
- **Smelt/smith** burn from the pouch, session-signed, zero popups.
- **NFTs skip the pouch**: `smith_*_and_keep` transfers the minted NFT to
  `cap.player()` **inside Move** — delivery to your real wallet is an on-chain
  guarantee no client can misdirect.
- **Collect to wallet** (button, session-signed, zero popups) sweeps pouch
  coins to your main wallet anytime; **End session** sweeps coins + leftover
  gas automatically and revokes the cap.
- A stolen session key could therefore burn pouch coins and gas — but can
  never extract NFTs or touch anything in your main wallet.

## Stack

- **Contracts**: Move 2024 (`move/ore_forge/`), four modules:
  - `ore.move` / `ingot.move` — ORE and INGOT currencies (`create_currency`)
  - `forge.move` — shared `Forge` (treasuries), mine/smelt/smith, Display setup
  - `session.move` — `SessionCap` (hand-rolled session keys)
- **Frontend**: SvelteKit (Svelte 5 runes) + Phaser 4 (`app/`), pnpm
- **Wallet**: `@builders-of-stuff/svelte-sui-wallet-adapter` v3
- **SDK**: `@mysten/sui` v2 (gRPC client via the adapter)
- **Art**: flat SVGs in `app/static/items/` — used by the app UI AND referenced
  by the on-chain CoinMetadata icons + NFT Display templates.

## Architecture decisions (and why)

- **No World object.** Player state IS the player's assets: coin balances and
  owned NFTs. Nothing to migrate, nothing to version, and every asset is
  wallet-visible/tradable by construction. The shared `Forge` exists only
  because minting needs `TreasuryCap` access from any transaction.
- **SessionCap is `key`-only** — can't be wrapped, traded, or generically
  transferred. Supports Clock expiry and an action budget, but **`ttl_ms = 0`
  / `actions = 0` mean forever/unlimited** (encoded as `u64::MAX` on-chain);
  the app mints forever-sessions that live until End session (`revoke`). No
  revocation registry (would put a second shared object in every gameplay tx).
- **ALL verbs are session-gated, including NFT minting** — the point is
  sign-once-then-mint-freely. The production-guidance "tier split" (minting
  demands the real wallet) is deliberately set aside; the `cap.player()`
  delivery invariant is the mitigation.
- **`mine` is a non-public `entry` fun** — required by the framework for
  functions consuming `Random` (blocks test-and-abort bias). Everything else
  is `public` for composability, with `*_and_keep` entry wrappers the frontend
  uses.
- **Smelt/smith take exact-amount coins** (`assert value == cost`); the client
  uses the SDK's `coinWithBalance` intent, which auto-merges the pouch's
  fragmented coins (every mine mints a new Coin object).
- **`create_currency` over `coin_registry`**: the modern registry flow needs an
  extra post-publish finalization tx; the classic (deprecated-but-working) API
  keeps manual deploys simple. Migrate if this outgrows prototype status.
- **Frontend reads events from BCS** (`event.bcs` parsed with `bcs.struct`),
  not `event.json` — the JSON shape varies across API implementations.
- **Type anchoring**: config carries `PACKAGE_ID` (latest, for moveCalls) and
  `ORIGINAL_PACKAGE_ID` (for coin types + event/type queries) because struct
  types anchor to the original package id across upgrades.
- **One transaction at a time** in the client: the cap, pouch coins, and gas
  coin are owned objects — concurrent submissions would equivocate. Clicks
  while a tx is in flight are ignored.
- **Images are hosted via raw.githubusercontent.com URLs** baked into the coin
  metadata and Display templates. ⚠️ The repo is currently **private**, so
  those URLs won't render for wallets until you either make the repo public or
  re-host (Walrus is the sui-native option) and update the `ICON_URL` /
  `*_IMAGE_URL` constants before publishing.
- Naming note: the middle area is **furnace/smelt** (ore → ingots) and the
  third **anvil/smith** (ingots → gear), the usual smelting-vs-smithing split.

## Milestones

- [x] **M1 — Contracts**: ore/ingot currencies, forge, session caps; unit
      tests green (`sui move test --build-env testnet`)
- [x] **M2 — Frontend skeleton**: SvelteKit + Phaser canvas with the three
      areas, wallet connect, HUD (pouch/wallet inventory, session panel, log)
- [x] **M3 — Chain wiring**: start/end session, mine, smelt, smith, collect —
      all built and type-checked (`pnpm check`, `pnpm build` green)
- [x] **M4 — Deploy & end-to-end test on testnet** — VERIFIED 2026-07-03: two
      full sessions played (mine → smelt → smith → sweep), all assets
      confirmed on-chain in the player's main wallet, session address left
      empty
- [ ] **M5 — Polish (optional)** ← YOU ARE HERE: sounds, better art,
      optimistic clicks with rollback, auto-collect cadence, top-up session
      gas button
- [ ] **M6 — Later ideas**: sponsored txs (drop the gas allowance), Kiosk +
      TransferPolicy for trading gear, ore types/tiers, leaderboard via custom
      indexer, migrate to `coin_registry`

## Progress log

- **2026-07-03** — Repo created. World-based contracts + full frontend written,
  unit-tested, building. Not deployed.
- **2026-07-03 (later)** — Session keys made the star: dropped the
  wallet-signs-smithing tier split, folded player creation into the
  session-start PTB — exactly one wallet popup per session.
- **2026-07-03 (later still)** — Forever sessions (`ttl 0` / `actions 0` →
  u64::MAX) + on-chain NFT delivery via `smith_*_and_keep`.
- **2026-07-03 (evening)** — **Big rework: cut the World entirely.** ORE and
  INGOT are now real Coin currencies (icons via CoinMetadata), gear is real
  Display-enabled NFTs, and the only shared object is the minimal `Forge`
  (treasury caps). Added the session "pouch" model + Collect-to-wallet sweep,
  SVG art for all four assets, and a post-publish `create_forge` step. Player
  registry, dynamic fields, `create_player`, AdminCap/versioning all deleted.
  Tests 7/7; `pnpm check`/`build` green. Still not deployed.
- **2026-07-03 (night)** — Repo made public (image URLs live). **PUBLISHED to
  testnet** (digest `3K34NTBx5vxHthuVy16aLQ4FRfs3xcGS8Ay3X8Csiars`). All ids
  recorded in `app/src/lib/sui/deployments.ts` — the committed source of truth
  (config.ts falls back to it, .env is gitignored). `create_forge` executed
  (digest `2kRUaGWjQ2zcpbXm6JVT536SZYBLYp7xcfYxMppDZcEC`) — treasuries wrapped
  into the shared Forge. **Fully deployed.**
- **2026-07-03 (late night)** — **M4 verified end-to-end on testnet.** Player
  `0xec6bc4…dfc23` ran two full sessions: one wallet signature each, then
  mining/smelting/smithing all popup-free. Final on-chain state: 13 ORE +
  1 INGOT (coins) + 1 Weapon + 1 Armour (NFTs) in the main wallet; session
  address swept completely clean (coins, caps, gas). Gotcha discovered:
  wallets hide unverified coins in an "unrecognized tokens" section and NFTs
  live under the Assets tab — the assets were "invisible" but present. The
  session-key experiment works.

## Testnet deployment record (2026-07-03)

Canonical copy lives in `app/src/lib/sui/deployments.ts`. Key ids:

| What | Id |
|---|---|
| Package (v1 = original) | `0x8a50310151ca116cc59dfd36b46d2367df854b932d0d5568b5ff6aa4a4bc2006` |
| **UpgradeCap** (guard this) | `0x015bd6218929a667c2a7eaad1a4b274ddc844af232bc3165b596689d61436aa6` |
| Publisher | `0x72d6eb9924e8c3170db1a8ab8c65556e869bf915ebb85a3f5255b08b014d7bfd` |
| Display\<Weapon\> | `0xfefcb9afe2a6707c5ee3400529bc1434fdeda8e356baa276666a001e2bdfcb13` |
| Display\<Armour\> | `0x5d9ddbed39dac8135a971a6c53994a1a7154539ffaeb79a847cbbc06e72df085` |
| TreasuryCap\<ORE\> | `0x8320635bfe3e2465bd8b0c0e189f79d0873cf4e87518babd25d0d12c161b7d27` |
| TreasuryCap\<INGOT\> | `0x52fe2b78a000a8d5c4f79289bc319537b6cb69643c71a259d3ada41511c609a8` |
| CoinMetadata\<ORE\> (frozen) | `0xc7c28b3411da1a57adec141f733b52cf5f92dbdbd08806bf14d58832b8057748` |
| CoinMetadata\<INGOT\> (frozen) | `0x0622c58beae7fcecf8e6f27f4cb210796f447d00ec0026273b496d82acc2670c` |
| **Forge (shared)** | `0xf736d18cdb593d5074b1394e68f1639185245f0b7296d51e3b3c6bfb70a9e3d3` |
| Publisher address | `0xe8468f320cf248052e931b3d0214e3f48049e86e28882b58579406cca7a51e86` |

## Deploy instructions (manual — do this to reach M4)

Contracts are NOT deployed yet. The frontend is coded as if they were; it just
needs the ids.

0. **Decide image hosting first** (wallets fetch these URLs): make this repo
   public, OR upload `app/static/items/*.svg` somewhere public (e.g. Walrus)
   and update the URL constants in `ore.move`, `ingot.move`, `forge.move`.

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
   - The two **TreasuryCap object ids** (types `TreasuryCap<...ore::ORE>` and
     `TreasuryCap<...ingot::INGOT>`) — they landed in your wallet
   - The `UpgradeCap`, `Publisher`, and two `Display` objects also land in
     your wallet; keep them (`Published.toml` is written automatically —
     commit it).

3. **Create the shared Forge** (one-time; locks both treasuries in):

   ```bash
   sui client call --package <PACKAGE_ID> --module forge --function create_forge \
     --args <ORE_TREASURY_CAP_ID> <INGOT_TREASURY_CAP_ID>
   ```

   Record the created shared object id — that's the **Forge ID**.

4. Configure the app:

   ```bash
   cd ../../app
   cp .env.example .env
   # set PUBLIC_PACKAGE_ID=<package id>
   # set PUBLIC_FORGE_ID=<forge object id>
   # leave PUBLIC_ORIGINAL_PACKAGE_ID empty until the first package upgrade
   ```

5. Run and play:

   ```bash
   pnpm install
   pnpm dev
   ```

   Flow to verify: connect wallet → **Start session** (the ONLY wallet popup:
   mints a forever-cap + funds the session key with 0.1 SUI) → click ore
   nodes / furnace / smith buttons, all with zero popups → smithed NFTs appear
   in your REAL wallet immediately (with images, if step 0 was done) →
   **Collect to wallet** moves pouch ORE/INGOT coins to your wallet (still no
   popup; check your wallet's token list shows ORE and INGOT) → reload the
   page: session persists → **End session** (cap revoked, pouch + gas swept
   back).

6. Update this file: tick M4, note the package/forge ids and any issues in the
   progress log.

### After a package upgrade (future)

`sui client upgrade --upgrade-capability <CAP_ID>`, then set
`PUBLIC_PACKAGE_ID` to the NEW id and `PUBLIC_ORIGINAL_PACKAGE_ID` to the FIRST
published id (coin types and event/type queries stay anchored there).

## Development commands

| What       | Where             | Command                              |
| ---------- | ----------------- | ------------------------------------ |
| Move tests | `move/ore_forge/` | `sui move test --build-env testnet`  |
| Move build | `move/ore_forge/` | `sui move build --build-env testnet` |
| Dev server | `app/`            | `pnpm dev`                           |
| Type check | `app/`            | `pnpm check`                         |
| Prod build | `app/`            | `pnpm build`                         |

## Known gaps / honest notes

- **Untested against a live network.** Unit tests and type checks pass, but the
  full client flow (event BCS parsing, `coinWithBalance` coin selection, gas
  allowance sizing) hasn't run against testnet yet — expect to shake out 1–2
  small issues at M4.
- **Image URLs point at a private repo** until step 0 of the deploy
  instructions is done — wallets will show broken images, everything else
  works.
- Mining latency = one consensus round-trip per click (~1–3 s on testnet); the
  UI blocks clicks while a tx is in flight. This is the known latency floor of
  on-chain play (reference doc §7b), not a bug.
- `adapter-auto` warns at build time that no deploy platform is detected —
  harmless for local dev; pick an adapter (or Walrus Sites + `adapter-static`)
  when hosting matters.
- The ephemeral key sits in `localStorage` — fine for its scoped authority
  (pouch coins + gas only), but that's the blast radius to keep in mind when
  raising the gas allowance.
