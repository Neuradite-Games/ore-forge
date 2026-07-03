import { env } from '$env/dynamic/public';

import { DEPLOYMENTS } from './deployments';

export type SuiNetwork = 'mainnet' | 'testnet' | 'devnet' | 'localnet';

export const NETWORK = (env.PUBLIC_SUI_NETWORK ?? 'testnet') as SuiNetwork;

const deployment = DEPLOYMENTS[NETWORK];

/** Env var wins when set to a real id; otherwise the committed deployment. */
function resolveId(envValue: string | undefined, fallback: string | undefined): string {
  if (envValue && envValue !== '0x0') return envValue;
  return fallback || '0x0';
}

/** moveCall targets — always the LATEST package id. */
export const PACKAGE_ID = resolveId(env.PUBLIC_PACKAGE_ID, deployment?.packageId);

/**
 * Type queries and event filters — always the ORIGINAL package id (struct
 * types stay anchored to the first published package across upgrades).
 * Same as PACKAGE_ID until the first upgrade.
 */
export const ORIGINAL_PACKAGE_ID = resolveId(
  env.PUBLIC_ORIGINAL_PACKAGE_ID,
  deployment?.originalPackageId || PACKAGE_ID,
);

/** The shared Forge (mint authority) created by forge::create_forge. */
export const FORGE_ID = resolveId(env.PUBLIC_FORGE_ID, deployment?.forgeId);

export const isConfigured = PACKAGE_ID !== '0x0' && FORGE_ID !== '0x0';

// Coin types anchor to the ORIGINAL package id, like all struct types.
export const ORE_TYPE = `${ORIGINAL_PACKAGE_ID}::ore::ORE`;
export const INGOT_TYPE = `${ORIGINAL_PACKAGE_ID}::ingot::INGOT`;

// Session parameters. 0 = forever / unlimited (on-chain sentinel u64::MAX):
// the session lives until you manually End session (revoke).
export const SESSION_TTL_MS = 0;
export const SESSION_ACTIONS = 0;
/** Gas allowance transferred to the ephemeral key: 0.1 SUI. Forever-sessions
 * can top this up any time by sending SUI to the session address. */
export const SESSION_GAS_MIST = 100_000_000n;

// Recipe costs — mirror the constants in forge.move.
export const SMELT_ORE_COST = 3;
export const WEAPON_INGOT_COST = 2;
export const ARMOUR_INGOT_COST = 3;
