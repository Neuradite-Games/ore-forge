<script lang="ts">
  import { onMount } from 'svelte';

  // Keep phaser out of the static module graph — imported lazily below.
  const GAME_WIDTH = 960;
  const GAME_HEIGHT = 540;

  let container: HTMLDivElement;

  onMount(() => {
    let game: import('phaser').Game | undefined;

    (async () => {
      const Phaser = (await import('phaser')).default;
      const { ForgeScene } = await import('./forge-scene');
      game = new Phaser.Game({
        type: Phaser.AUTO,
        parent: container,
        width: GAME_WIDTH,
        height: GAME_HEIGHT,
        backgroundColor: '#14100c',
        scene: [ForgeScene],
        scale: {
          mode: Phaser.Scale.FIT,
          autoCenter: Phaser.Scale.CENTER_BOTH,
        },
      });
    })();

    return () => game?.destroy(true);
  });
</script>

<div class="game" bind:this={container}></div>

<style>
  .game {
    width: 100%;
    max-width: 960px;
    aspect-ratio: 16 / 9;
    border-radius: 8px;
    overflow: hidden;
  }
</style>
