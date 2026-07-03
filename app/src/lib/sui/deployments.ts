/**
 * Committed record of every on-chain deployment — .env is gitignored, so THIS
 * file is the durable source of truth for ids (they're public data, safe to
 * commit). config.ts falls back to these values when env vars are unset.
 *
 * Keep every id from the publish output here, especially the UpgradeCap —
 * losing track of it means losing the ability to upgrade the package.
 */
export interface Deployment {
  /** Latest package id — moveCall targets. */
  packageId: string;
  /** First-published id — type/event queries anchor here across upgrades. */
  originalPackageId: string;
  /** Shared Forge (mint authority) from forge::create_forge. */
  forgeId: string;
  /** 0x2::package::UpgradeCap — REQUIRED to ever upgrade the package. */
  upgradeCap: string;
  /** 0x2::package::Publisher — needed to edit Display templates later. */
  publisher: string;
  /** Display<Weapon> / Display<Armour> — edit these to change NFT metadata. */
  weaponDisplay: string;
  armourDisplay: string;
  /** Treasury caps now live INSIDE the shared Forge (create_forge consumed
   * them); ids kept for the historical record. */
  oreTreasuryCap: string;
  ingotTreasuryCap: string;
  /** Frozen coin metadata objects (symbol/icon). */
  oreCoinMetadata: string;
  ingotCoinMetadata: string;
  publishDigest: string;
  publisherAddress: string;
}

export const DEPLOYMENTS: Partial<Record<string, Deployment>> = {
  testnet: {
    packageId: '0x8a50310151ca116cc59dfd36b46d2367df854b932d0d5568b5ff6aa4a4bc2006',
    originalPackageId:
      '0x8a50310151ca116cc59dfd36b46d2367df854b932d0d5568b5ff6aa4a4bc2006',
    // TODO: fill in after running forge::create_forge (see PROJECT.md step 3).
    forgeId: '',
    upgradeCap: '0x015bd6218929a667c2a7eaad1a4b274ddc844af232bc3165b596689d61436aa6',
    publisher: '0x72d6eb9924e8c3170db1a8ab8c65556e869bf915ebb85a3f5255b08b014d7bfd',
    weaponDisplay:
      '0xfefcb9afe2a6707c5ee3400529bc1434fdeda8e356baa276666a001e2bdfcb13',
    armourDisplay:
      '0x5d9ddbed39dac8135a971a6c53994a1a7154539ffaeb79a847cbbc06e72df085',
    oreTreasuryCap:
      '0x8320635bfe3e2465bd8b0c0e189f79d0873cf4e87518babd25d0d12c161b7d27',
    ingotTreasuryCap:
      '0x52fe2b78a000a8d5c4f79289bc319537b6cb69643c71a259d3ada41511c609a8',
    oreCoinMetadata:
      '0xc7c28b3411da1a57adec141f733b52cf5f92dbdbd08806bf14d58832b8057748',
    ingotCoinMetadata:
      '0x0622c58beae7fcecf8e6f27f4cb210796f447d00ec0026273b496d82acc2670c',
    publishDigest: '3K34NTBx5vxHthuVy16aLQ4FRfs3xcGS8Ay3X8Csiars',
    publisherAddress:
      '0xe8468f320cf248052e931b3d0214e3f48049e86e28882b58579406cca7a51e86',
  },
};
