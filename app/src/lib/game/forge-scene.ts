/**
 * Single Phaser scene with three areas: the ore field (click nodes to mine),
 * the furnace (smelt ore into ingots), and the anvil (smith gear).
 *
 * The scene renders intent and feedback only — every game-state mutation
 * happens on-chain. Clicks emit intents on the event bus; the Svelte side
 * submits transactions and reports outcomes back.
 */
import Phaser from 'phaser';

import { gameEvents } from './event-bus';

export const GAME_WIDTH = 960;
export const GAME_HEIGHT = 540;

const PANEL_WIDTH = GAME_WIDTH / 3;

const COLORS = {
  fieldBg: 0x1c2418,
  furnaceBg: 0x241a14,
  anvilBg: 0x1a1c24,
  rock: 0x6b6f76,
  rockDark: 0x51555c,
  oreSparkle: 0xffb347,
  furnaceBody: 0x4a3428,
  fire: 0xff6b35,
  anvil: 0x3a3f4b,
  button: 0x2d3446,
  buttonHover: 0x3d4660,
  text: 0xe8e0d0,
};

interface OreNode {
  container: Phaser.GameObjects.Container;
  depleted: boolean;
}

export class ForgeScene extends Phaser.Scene {
  private oreNodes: OreNode[] = [];
  private furnace!: Phaser.GameObjects.Container;
  private fire!: Phaser.GameObjects.Arc;
  private busyText!: Phaser.GameObjects.Text;
  private unsubscribers: (() => void)[] = [];

  constructor() {
    super('forge');
  }

  create() {
    this.drawPanels();
    this.createOreField();
    this.createFurnace();
    this.createAnvil();

    this.busyText = this.add
      .text(GAME_WIDTH / 2, GAME_HEIGHT - 18, '⏳ transaction in flight…', {
        fontSize: '14px',
        color: '#ffd479',
      })
      .setOrigin(0.5)
      .setVisible(false);

    this.unsubscribers = [
      gameEvents.on('mine-result', ({ nodeId, amount }) =>
        this.onMined(nodeId, amount),
      ),
      gameEvents.on('mine-failed', ({ nodeId }) => this.onMineFailed(nodeId)),
      gameEvents.on('smelt-result', () => this.onSmelted()),
      gameEvents.on('smith-result', ({ kind }) => this.onSmithed(kind)),
      gameEvents.on('busy', ({ busy }) => this.busyText.setVisible(busy)),
    ];

    this.events.once(Phaser.Scenes.Events.SHUTDOWN, () => {
      this.unsubscribers.forEach((unsubscribe) => unsubscribe());
    });
  }

  // === layout ===

  private drawPanels() {
    const panels = [
      { x: 0, color: COLORS.fieldBg, label: '⛏  ORE FIELD', hint: 'click an ore node' },
      {
        x: PANEL_WIDTH,
        color: COLORS.furnaceBg,
        label: '🔥  FURNACE',
        hint: '3 ore → 1 ingot',
      },
      {
        x: PANEL_WIDTH * 2,
        color: COLORS.anvilBg,
        label: '⚒  ANVIL',
        hint: 'smith gear — no popups',
      },
    ];
    for (const panel of panels) {
      this.add
        .rectangle(panel.x, 0, PANEL_WIDTH, GAME_HEIGHT, panel.color)
        .setOrigin(0);
      this.add
        .text(panel.x + PANEL_WIDTH / 2, 28, panel.label, {
          fontSize: '20px',
          fontStyle: 'bold',
          color: '#e8e0d0',
        })
        .setOrigin(0.5);
      this.add
        .text(panel.x + PANEL_WIDTH / 2, 52, panel.hint, {
          fontSize: '12px',
          color: '#9a917e',
        })
        .setOrigin(0.5);
    }
    this.add.rectangle(PANEL_WIDTH, 0, 2, GAME_HEIGHT, 0x000000, 0.4).setOrigin(0);
    this.add.rectangle(PANEL_WIDTH * 2, 0, 2, GAME_HEIGHT, 0x000000, 0.4).setOrigin(0);
  }

  // === ore field ===

  private createOreField() {
    const positions = [
      { x: 80, y: 140 },
      { x: 210, y: 170 },
      { x: 130, y: 260 },
      { x: 250, y: 310 },
      { x: 90, y: 380 },
      { x: 190, y: 450 },
    ];
    positions.forEach((pos, nodeId) => {
      const rock = this.add.circle(0, 0, 30, COLORS.rock);
      const shadow = this.add.circle(4, 6, 30, COLORS.rockDark).setDepth(-1);
      const sparkles = [-12, 2, 10].map((dx, i) =>
        this.add.circle(dx, (i - 1) * 9, 4, COLORS.oreSparkle),
      );
      const container = this.add.container(pos.x, pos.y, [shadow, rock, ...sparkles]);
      container.setSize(64, 64);
      container.setInteractive({ useHandCursor: true });
      container.on('pointerdown', () => {
        const node = this.oreNodes[nodeId];
        if (node.depleted) return;
        this.tweens.add({ targets: container, scale: 0.85, duration: 80, yoyo: true });
        gameEvents.emit('mine', { nodeId });
      });
      this.oreNodes.push({ container, depleted: false });
    });
  }

  private onMined(nodeId: number, amount: number) {
    const node = this.oreNodes[nodeId];
    if (!node) return;
    this.floatText(
      node.container.x,
      node.container.y - 40,
      `+${amount} ore`,
      '#ffb347',
    );
    node.depleted = true;
    node.container.setAlpha(0.25);
    // Respawn is purely visual — the chain doesn't track individual nodes.
    this.time.delayedCall(2000, () => {
      node.depleted = false;
      node.container.setAlpha(1);
      this.tweens.add({
        targets: node.container,
        scale: { from: 0.6, to: 1 },
        duration: 200,
      });
    });
  }

  private onMineFailed(nodeId: number) {
    const node = this.oreNodes[nodeId];
    if (!node) return;
    this.floatText(node.container.x, node.container.y - 40, '✗', '#ff6b6b');
  }

  // === furnace ===

  private createFurnace() {
    const centerX = PANEL_WIDTH * 1.5;
    const centerY = 300;

    const body = this.add.rectangle(0, 0, 130, 150, COLORS.furnaceBody);
    const opening = this.add.rectangle(0, 30, 80, 60, 0x1a0f0a);
    this.fire = this.add.circle(0, 30, 26, COLORS.fire);
    const chimney = this.add.rectangle(35, -95, 30, 40, COLORS.furnaceBody);
    const label = this.add
      .text(0, 105, 'SMELT', { fontSize: '16px', fontStyle: 'bold', color: '#ffd479' })
      .setOrigin(0.5);

    this.furnace = this.add.container(centerX, centerY, [
      chimney,
      body,
      opening,
      this.fire,
      label,
    ]);
    this.furnace.setSize(140, 160);
    this.furnace.setInteractive({ useHandCursor: true });
    this.furnace.on('pointerdown', () => {
      this.tweens.add({ targets: this.furnace, scale: 0.95, duration: 80, yoyo: true });
      gameEvents.emit('smelt');
    });

    this.tweens.add({
      targets: this.fire,
      scale: { from: 0.85, to: 1.15 },
      duration: 450,
      yoyo: true,
      repeat: -1,
    });
  }

  private onSmelted() {
    this.floatText(this.furnace.x, this.furnace.y - 100, '+1 ingot 🧱', '#ffd479');
    this.tweens.add({
      targets: this.fire,
      scale: { from: 1.8, to: 1 },
      duration: 400,
    });
  }

  // === anvil ===

  private createAnvil() {
    const centerX = PANEL_WIDTH * 2.5;

    // anvil silhouette
    const top = this.add.rectangle(0, -18, 120, 26, COLORS.anvil);
    const horn = this.add.triangle(74, -18, 0, -13, 0, 13, 34, 0, COLORS.anvil);
    const waist = this.add.rectangle(-10, 8, 40, 26, COLORS.anvil);
    const base = this.add.rectangle(-10, 30, 90, 18, COLORS.anvil);
    this.add.container(centerX, 170, [top, horn, waist, base]);

    this.createSmithButton(centerX, 300, '⚔  SWORD', '2 ingots', () =>
      gameEvents.emit('smith-weapon'),
    );
    this.createSmithButton(centerX, 400, '🛡  ARMOUR', '3 ingots', () =>
      gameEvents.emit('smith-armour'),
    );
  }

  private createSmithButton(
    x: number,
    y: number,
    title: string,
    cost: string,
    onClick: () => void,
  ) {
    const background = this.add
      .rectangle(0, 0, 220, 64, COLORS.button)
      .setStrokeStyle(2, 0x4d5a7a);
    const titleText = this.add
      .text(0, -12, title, { fontSize: '18px', fontStyle: 'bold', color: '#e8e0d0' })
      .setOrigin(0.5);
    const costText = this.add
      .text(0, 14, cost, { fontSize: '12px', color: '#9a917e' })
      .setOrigin(0.5);
    const button = this.add.container(x, y, [background, titleText, costText]);
    button.setSize(220, 64);
    button.setInteractive({ useHandCursor: true });
    button.on('pointerover', () => background.setFillStyle(COLORS.buttonHover));
    button.on('pointerout', () => background.setFillStyle(COLORS.button));
    button.on('pointerdown', () => {
      this.tweens.add({ targets: button, scale: 0.95, duration: 80, yoyo: true });
      onClick();
    });
  }

  private onSmithed(kind: 'weapon' | 'armour') {
    const centerX = PANEL_WIDTH * 2.5;
    const icon = kind === 'weapon' ? '⚔️' : '🛡️';
    this.floatText(centerX, 240, `${icon} smithed!`, '#8fd3ff', '28px');
  }

  // === helpers ===

  private floatText(
    x: number,
    y: number,
    message: string,
    color: string,
    size = '18px',
  ) {
    const text = this.add
      .text(x, y, message, { fontSize: size, fontStyle: 'bold', color })
      .setOrigin(0.5);
    this.tweens.add({
      targets: text,
      y: y - 50,
      alpha: 0,
      duration: 1200,
      ease: 'Cubic.easeOut',
      onComplete: () => text.destroy(),
    });
  }
}
