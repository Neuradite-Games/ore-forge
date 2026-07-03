# Ore Forge

A simple on-chain ore mining game on Sui. Read `PROJECT.md` first — it holds the
context, architecture decisions, milestones, and current progress.

## Project Structure

- `move/ore_forge/` — Move smart contracts (world, session keys, mining/smithing)
- `app/` — SvelteKit + Phaser frontend (pnpm)

## Sui Development Skills

Install community-maintained skills for Sui development:

```sh
npx skills https://github.com/MystenLabs/skills
```

## Sui SDK Reference

Every `@mysten/*` package ships LLM documentation in its `docs/` directory. When
working with these packages, find the relevant docs by looking for
`docs/llms-index.md` files inside `app/node_modules/@mysten/*/`. Read the index
first to find the page you need, then read that page for details.

Also query the Sui documentation MCP server (`https://sui.mcp.kapa.ai`) when
available for up-to-date answers.

## Official Resources

When unsure about Move patterns or Sui APIs, consult these sources. Do not guess
or extrapolate from other blockchains.

- Move Book: https://move-book.com (use https://move-book.com/llms.txt)
- Sui Docs: https://docs.sui.io (use https://docs.sui.io/llms.txt)
- Sui Move examples: https://github.com/MystenLabs/sui/tree/main/examples/move
- Condensed local reference: `../docs/sui-reference.md` in the parent games repo

## Project Rules

- Move: 2024 edition, method syntax, `#[error]` constants, events on every
  interesting action. Build/test with `sui move build --build-env testnet` and
  `sui move test --build-env testnet` from `move/ore_forge/`.
- Frontend: pnpm, Prettier (88 cols, spaces, single quotes), kebab-case file
  names, Svelte 5 runes. Type-check with `pnpm check`, verify with `pnpm build`.
- Parse on-chain events from BCS (`event.bcs`), not the `json` field — the JSON
  shape varies between API implementations.
- Session-gated verbs (mine, smelt) must stay non-extractive; anything minting
  or moving assets requires the real wallet signature.
