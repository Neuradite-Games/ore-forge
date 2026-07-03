import type { SessionInfo } from '$lib/sui/session';
import type { EquipmentItem } from '$lib/sui/forge-client';

export const gameState = $state({
  hasPlayer: false,
  ore: 0,
  ingots: 0,
  weaponsSmithed: 0,
  armourSmithed: 0,
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
