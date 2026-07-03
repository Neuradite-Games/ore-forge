/**
 * Transaction builders and queries for the ore_forge package.
 *
 * All gameplay transactions are signed by the session key, whose address is
 * the tx sender: `coinWithBalance` therefore selects ORE/INGOT coins from the
 * session pouch automatically, and mine's output lands there too. NFTs are
 * delivered to the real wallet inside Move (`smith_*_and_keep`).
 *
 * Events are parsed from BCS (not the `json` field) because the JSON shape
 * varies between API implementations.
 */
import { bcs } from '@mysten/sui/bcs';
import type { SuiGrpcClient } from '@mysten/sui/grpc';
import { coinWithBalance, Transaction } from '@mysten/sui/transactions';

import {
  ARMOUR_INGOT_COST,
  FORGE_ID,
  INGOT_TYPE,
  ORE_TYPE,
  ORIGINAL_PACKAGE_ID,
  PACKAGE_ID,
  SMELT_ORE_COST,
  WEAPON_INGOT_COST,
} from './config';

export interface CoinBalances {
  ore: number;
  ingots: number;
}

export interface EquipmentItem {
  objectId: string;
  kind: 'weapon' | 'armour';
}

// === BCS event schemas (field order mirrors the Move structs) ===

export const OreMinedBcs = bcs.struct('OreMined', {
  player: bcs.Address,
  amount: bcs.u64(),
});

// === Transaction builders ===

export function buildMineTx(capId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::forge::mine`,
    arguments: [
      tx.object(FORGE_ID),
      tx.object(capId),
      tx.object.random(),
      tx.object.clock(),
    ],
  });
  return tx;
}

export function buildSmeltTx(capId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::forge::smelt_and_keep`,
    arguments: [
      tx.object(FORGE_ID),
      tx.object(capId),
      coinWithBalance({ type: ORE_TYPE, balance: BigInt(SMELT_ORE_COST) }),
      tx.object.clock(),
    ],
  });
  return tx;
}

export function buildSmithTx(kind: 'weapon' | 'armour', capId: string): Transaction {
  const cost = kind === 'weapon' ? WEAPON_INGOT_COST : ARMOUR_INGOT_COST;
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::forge::smith_${kind}_and_keep`,
    arguments: [
      tx.object(FORGE_ID),
      tx.object(capId),
      coinWithBalance({ type: INGOT_TYPE, balance: BigInt(cost) }),
      tx.object.clock(),
    ],
  });
  return tx;
}

// === Queries ===

/** ORE/INGOT balances for any address (real coins — same query wallets run). */
export async function fetchBalances(
  client: SuiGrpcClient,
  owner: string,
): Promise<CoinBalances> {
  const [ore, ingots] = await Promise.all([
    client.core.getBalance({ owner, coinType: ORE_TYPE }),
    client.core.getBalance({ owner, coinType: INGOT_TYPE }),
  ]);
  return {
    ore: Number(ore.balance.balance),
    ingots: Number(ingots.balance.balance),
  };
}

/** Object ids of all ORE/INGOT coins an address holds (for sweeping). */
export async function fetchCoinIds(
  client: SuiGrpcClient,
  owner: string,
): Promise<string[]> {
  const ids: string[] = [];
  for (const coinType of [ORE_TYPE, INGOT_TYPE]) {
    let cursor: string | null = null;
    do {
      const page: Awaited<ReturnType<typeof client.core.listCoins>> =
        await client.core.listCoins({
          owner,
          coinType,
          ...(cursor ? { cursor } : {}),
        });
      for (const coin of page.objects) {
        ids.push(coin.objectId);
      }
      cursor = page.cursor ?? null;
    } while (cursor);
  }
  return ids;
}

/** All Weapon / Armour NFTs owned by the connected wallet. */
export async function fetchEquipment(
  client: SuiGrpcClient,
  owner: string,
): Promise<EquipmentItem[]> {
  const kinds = [
    { kind: 'weapon' as const, type: `${ORIGINAL_PACKAGE_ID}::forge::Weapon` },
    { kind: 'armour' as const, type: `${ORIGINAL_PACKAGE_ID}::forge::Armour` },
  ];
  const items: EquipmentItem[] = [];
  for (const { kind, type } of kinds) {
    let cursor: string | null = null;
    do {
      const page: Awaited<ReturnType<typeof client.core.listOwnedObjects>> =
        await client.core.listOwnedObjects({
          owner,
          type,
          ...(cursor ? { cursor } : {}),
        });
      for (const obj of page.objects) {
        items.push({ objectId: obj.objectId, kind });
      }
      cursor = page.cursor ?? null;
    } while (cursor);
  }
  return items;
}
