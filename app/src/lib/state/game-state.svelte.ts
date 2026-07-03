import type { SessionInfo } from '$lib/sui/session';
import type { EquipmentItem } from '$lib/sui/forge-client';

export const gameState = $state({
  /** Session pouch — real ORE/INGOT coins held by the session address. */
  pouchOre: 0,
  pouchIngots: 0,
  /** Balances already in the player's main wallet. */
  walletOre: 0,
  walletIngots: 0,
  /** Weapon/Armour NFTs in the player's main wallet. */
  equipment: [] as EquipmentItem[],
  session: null as SessionInfo | null,
  /** Verb currently in flight — owned objects allow one tx at a time. */
  pending: null as string | null,
  log: [] as { time: string; message: string }[],
});

export function addLog(message: string) {
  const time = new Date().toLocaleTimeString();
  gameState.log.unshift({ time, message });
  if (gameState.log.length > 50) gameState.log.pop();
}
