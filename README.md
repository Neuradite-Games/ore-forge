# ⛏ Ore Forge

A simple on-chain ore mining game on Sui. Click ore nodes to mine, smelt ore
into ingots at the furnace, smith ingots into swords and armour at the anvil —
every action is a Sui transaction, and mining/smelting run **without wallet
popups** via a hand-rolled session-key pattern (`SessionCap`).

- **Contracts**: Move 2024 — `move/ore_forge/` (ORE/INGOT coins, NFT gear, session caps)
- **Client**: SvelteKit + Phaser + `@builders-of-stuff/svelte-sui-wallet-adapter` — `app/`

See **[PROJECT.md](./PROJECT.md)** for the architecture, milestones, current
progress, and deploy instructions.

## Quick start

```bash
# contracts
cd move/ore_forge && sui move test --build-env testnet

# app (needs .env — see PROJECT.md "Deploy instructions")
cd app && pnpm install && pnpm dev
```
