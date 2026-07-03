import { env } from '$env/dynamic/public';

export type SuiNetwork = 'mainnet' | 'testnet' | 'devnet' | 'localnet';

export const NETWORK = (env.PUBLIC_SUI_NETWORK ?? 'testnet') as SuiNetwork;

/** moveCall targets — always the LATEST package id. */
export const PACKAGE_ID = env.PUBLIC_PACKAGE_ID ?? '0x0';

/**
 * Type queries and event filters — always the ORIGINAL package id (struct
 * types stay anchored to the first published package across upgrades).
 * Same as PACKAGE_ID until the first upgrade.
 */
export const ORIGINAL_PACKAGE_ID = env.PUBLIC_ORIGINAL_PACKAGE_ID || PACKAGE_ID;

/** The shared World object created by the package's init. */
export const WORLD_ID = env.PUBLIC_WORLD_ID ?? '0x0';

export const isConfigured = PACKAGE_ID !== '0x0' && WORLD_ID !== '0x0';

// Session parameters (must respect session.move's MAX_TTL_MS of 8h).
export const SESSION_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours
export const SESSION_ACTIONS = 200;
/** Gas allowance transferred to the ephemeral key: 0.05 SUI. */
export const SESSION_GAS_MIST = 50_000_000n;

// Recipe costs — mirror the constants in forge.move.
export const SMELT_ORE_COST = 3;
export const WEAPON_INGOT_COST = 2;
export const ARMOUR_INGOT_COST = 3;
