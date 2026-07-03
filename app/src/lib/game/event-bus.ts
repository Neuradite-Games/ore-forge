/**
 * Tiny typed emitter bridging Phaser and Svelte (framework-free so it can be
 * imported during SSR without pulling Phaser in).
 *
 * Phaser -> Svelte: player intent ('mine', 'smelt', 'smith-weapon', ...).
 * Svelte -> Phaser: transaction outcomes ('mine-result', 'smelt-failed', ...).
 */

export interface GameEvents {
  // intents (Phaser -> Svelte)
  mine: { nodeId: number };
  smelt: undefined;
  'smith-weapon': undefined;
  'smith-armour': undefined;
  // outcomes (Svelte -> Phaser)
  'mine-result': { nodeId: number; amount: number };
  'mine-failed': { nodeId: number };
  'smelt-result': undefined;
  'smelt-failed': undefined;
  'smith-result': { kind: 'weapon' | 'armour' };
  'smith-failed': { kind: 'weapon' | 'armour' };
  busy: { busy: boolean };
}

type Handler<T> = (payload: T) => void;

class EventBus {
  private handlers = new Map<string, Set<Handler<never>>>();

  on<K extends keyof GameEvents>(event: K, handler: Handler<GameEvents[K]>) {
    if (!this.handlers.has(event)) this.handlers.set(event, new Set());
    this.handlers.get(event)!.add(handler as Handler<never>);
    return () => this.off(event, handler);
  }

  off<K extends keyof GameEvents>(event: K, handler: Handler<GameEvents[K]>) {
    this.handlers.get(event)?.delete(handler as Handler<never>);
  }

  emit<K extends keyof GameEvents>(
    event: K,
    ...args: GameEvents[K] extends undefined ? [] : [GameEvents[K]]
  ) {
    this.handlers.get(event)?.forEach((handler) => {
      (handler as Handler<GameEvents[K] | undefined>)(args[0]);
    });
  }

  clear() {
    this.handlers.clear();
  }
}

export const gameEvents = new EventBus();
