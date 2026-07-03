/**
 * Transaction builders and queries for the ore_forge package.
 *
 * Events are parsed from BCS (not the `json` field) because the JSON shape
 * varies between API implementations.
 */
import { bcs } from '@mysten/sui/bcs';
import type { SuiGrpcClient } from '@mysten/sui/grpc';
import { Transaction } from '@mysten/sui/transactions';

import { ORIGINAL_PACKAGE_ID, PACKAGE_ID, WORLD_ID } from './config';

export interface PlayerStats {
  ore: number;
  ingots: number;
  weaponsSmithed: number;
  armourSmithed: number;
}

export interface EquipmentItem {
  objectId: string;
  kind: 'weapon' | 'armour';
}

// === BCS schemas (field order mirrors the Move structs) ===

const PlayerBcs = bcs.struct('Player', {
  ore: bcs.u64(),
  ingots: bcs.u64(),
  weaponsSmithed: bcs.u64(),
  armourSmithed: bcs.u64(),
});

export const OreMinedBcs = bcs.struct('OreMined', {
  player: bcs.Address,
  amount: bcs.u64(),
  oreTotal: bcs.u64(),
});

export const IngotSmeltedBcs = bcs.struct('IngotSmelted', {
  player: bcs.Address,
  oreSpent: bcs.u64(),
  ingotTotal: bcs.u64(),
});

// === Transaction builders ===

export function buildCreatePlayerTx(): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::forge::create_player`,
    arguments: [tx.object(WORLD_ID)],
  });
  return tx;
}

export function buildMineTx(capId: string): Transaction {
  const tx = new Transaction();
  tx.moveCall({
    target: `${PACKAGE_ID}::forge::mine`,
    arguments: [
      tx.object(WORLD_ID),
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
    target: `${PACKAGE_ID}::forge::smelt`,
    arguments: [tx.object(WORLD_ID), tx.object(capId), tx.object.clock()],
  });
  return tx;
}

/** Smithing returns the minted item; the PTB sends it to the player. */
export function buildSmithTx(kind: 'weapon' | 'armour', player: string): Transaction {
  const tx = new Transaction();
  const item = tx.moveCall({
    target: `${PACKAGE_ID}::forge::smith_${kind}`,
    arguments: [tx.object(WORLD_ID)],
  });
  tx.transferObjects([item], tx.pure.address(player));
  return tx;
}

// === Queries ===

/**
 * Player state lives in a dynamic field on the shared World, keyed by
 * `forge::PlayerKey(address)` — a positional struct whose BCS is just the
 * address. Returns null when no player exists yet.
 */
export async function fetchPlayerStats(
  client: SuiGrpcClient,
  player: string,
): Promise<PlayerStats | null> {
  try {
    const { dynamicField } = await client.core.getDynamicField({
      parentId: WORLD_ID,
      name: {
        type: `${ORIGINAL_PACKAGE_ID}::forge::PlayerKey`,
        bcs: bcs.Address.serialize(player).toBytes(),
      },
    });
    const parsed = PlayerBcs.parse(dynamicField.value.bcs);
    return {
      ore: Number(parsed.ore),
      ingots: Number(parsed.ingots),
      weaponsSmithed: Number(parsed.weaponsSmithed),
      armourSmithed: Number(parsed.armourSmithed),
    };
  } catch {
    return null;
  }
}

/** All Weapon / Armour objects owned by the connected wallet. */
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
