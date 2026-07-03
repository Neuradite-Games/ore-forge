/// Ore Forge core loop: mine ORE coins → smelt INGOT coins at the furnace →
/// smith Weapon/Armour NFTs at the anvil.
///
/// There is no world/registry object — player state IS the player's assets:
/// ORE and INGOT are real fungible coins, gear is real `key, store` NFTs with
/// Object Display. The only shared object is the minimal `Forge`, which holds
/// the two treasury caps so any transaction can mint/burn.
///
/// Session-key flow (see session.move): the ephemeral key signs everything.
/// Because spending an owned coin requires its owner's signature, working
/// materials (ORE/INGOT) are minted to the session address — a real wallet
/// the session key controls — and swept to the player's main wallet on
/// demand or at session end. NFTs skip the pouch entirely: `*_and_keep`
/// delivers them to `cap.player()` inside Move.
///
/// `mine` consumes on-chain randomness, so it must be a non-public `entry`
/// function (the framework blocks test-and-abort bias attacks).
module ore_forge::forge;

use ore_forge::ingot::INGOT;
use ore_forge::ore::ORE;
use ore_forge::session::SessionCap;
use sui::clock::Clock;
use sui::coin::{Coin, TreasuryCap};
use sui::display;
use sui::event;
use sui::package;
use sui::random::Random;

/// Mining yields 1..=MAX_ORE_PER_MINE per swing.
const MAX_ORE_PER_MINE: u64 = 3;
/// Furnace recipe: ore in, one ingot out.
const SMELT_ORE_COST: u64 = 3;
/// Anvil recipes.
const WEAPON_INGOT_COST: u64 = 2;
const ARMOUR_INGOT_COST: u64 = 3;

/// Update after re-hosting the images (e.g. Walrus); wallets need public URLs.
const WEAPON_IMAGE_URL: vector<u8> =
    b"https://raw.githubusercontent.com/Neuradite-Games/ore-forge/main/app/static/items/sword.svg";
const ARMOUR_IMAGE_URL: vector<u8> =
    b"https://raw.githubusercontent.com/Neuradite-Games/ore-forge/main/app/static/items/armour.svg";

#[error]
const EWrongOreAmount: vector<u8> = b"Smelting takes exactly 3 ore";
#[error]
const EWrongIngotAmount: vector<u8> = b"Wrong ingot amount for this recipe";

/// One-time witness — claims the Publisher for Object Display.
public struct FORGE has drop {}

/// Minimal shared mint authority. Not a world: no player registry, no
/// per-player state — just the treasuries the recipes need.
public struct Forge has key {
    id: UID,
    ore_treasury: TreasuryCap<ORE>,
    ingot_treasury: TreasuryCap<INGOT>,
}

/// Tradable gear: `key, store` NFTs rendered by wallets via Display.
public struct Weapon has key, store {
    id: UID,
    ingots_used: u64,
}

public struct Armour has key, store {
    id: UID,
    ingots_used: u64,
}

// === Events ===

public struct OreMined has copy, drop {
    player: address,
    amount: u64,
}

public struct IngotSmelted has copy, drop {
    player: address,
    ore_spent: u64,
}

public struct WeaponSmithed has copy, drop {
    player: address,
    weapon_id: ID,
}

public struct ArmourSmithed has copy, drop {
    player: address,
    armour_id: ID,
}

/// Claims the Publisher and registers Display templates so wallets and
/// explorers render the NFTs with names and images.
fun init(otw: FORGE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut weapon_display = display::new_with_fields<Weapon>(
        &publisher,
        vector[b"name".to_string(), b"description".to_string(), b"image_url".to_string()],
        vector[
            b"Ore Forge Sword".to_string(),
            b"Smithed from {ingots_used} ingots at the Ore Forge anvil.".to_string(),
            WEAPON_IMAGE_URL.to_string(),
        ],
        ctx,
    );
    weapon_display.update_version();

    let mut armour_display = display::new_with_fields<Armour>(
        &publisher,
        vector[b"name".to_string(), b"description".to_string(), b"image_url".to_string()],
        vector[
            b"Ore Forge Armour".to_string(),
            b"Smithed from {ingots_used} ingots at the Ore Forge anvil.".to_string(),
            ARMOUR_IMAGE_URL.to_string(),
        ],
        ctx,
    );
    armour_display.update_version();

    transfer::public_transfer(weapon_display, ctx.sender());
    transfer::public_transfer(armour_display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

/// One-time post-publish setup: lock both treasuries into the shared Forge.
/// (Two currencies need two one-time witnesses, so the caps are minted in
/// ore.move / ingot.move inits and combined here by the publisher.)
public fun create_forge(
    ore_treasury: TreasuryCap<ORE>,
    ingot_treasury: TreasuryCap<INGOT>,
    ctx: &mut TxContext,
) {
    transfer::share_object(Forge {
        id: object::new(ctx),
        ore_treasury,
        ingot_treasury,
    });
}

// === Gameplay (all session-signed; ctx.sender() is the session address) ===

/// Swing at an ore node: mints 1..=3 ORE to the session pouch. Non-public
/// `entry` is mandatory — this consumes `Random` at 0x8.
entry fun mine(
    forge: &mut Forge,
    cap: &mut SessionCap,
    r: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    cap.consume_action(clock);
    let mut gen = r.new_generator(ctx);
    let amount = gen.generate_u64_in_range(1, MAX_ORE_PER_MINE);
    let ore = forge.ore_treasury.mint(amount, ctx);
    transfer::public_transfer(ore, ctx.sender());
    event::emit(OreMined { player: cap.player(), amount });
}

/// Furnace: burn exactly 3 ORE, get one INGOT back.
public fun smelt(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ore: Coin<ORE>,
    clock: &Clock,
    ctx: &mut TxContext,
): Coin<INGOT> {
    cap.consume_action(clock);
    assert!(ore.value() == SMELT_ORE_COST, EWrongOreAmount);
    forge.ore_treasury.burn(ore);
    event::emit(IngotSmelted { player: cap.player(), ore_spent: SMELT_ORE_COST });
    forge.ingot_treasury.mint(1, ctx)
}

entry fun smelt_and_keep(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ore: Coin<ORE>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let ingot = smelt(forge, cap, ore, clock, ctx);
    transfer::public_transfer(ingot, ctx.sender());
}

// === Anvil: smithing burns INGOT coins and mints NFTs ===

/// Returns the Weapon; the calling PTB decides where it goes.
public fun smith_weapon(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ingots: Coin<INGOT>,
    clock: &Clock,
    ctx: &mut TxContext,
): Weapon {
    cap.consume_action(clock);
    assert!(ingots.value() == WEAPON_INGOT_COST, EWrongIngotAmount);
    forge.ingot_treasury.burn(ingots);
    let weapon = Weapon { id: object::new(ctx), ingots_used: WEAPON_INGOT_COST };
    event::emit(WeaponSmithed { player: cap.player(), weapon_id: weapon.id.to_inner() });
    weapon
}

public fun smith_armour(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ingots: Coin<INGOT>,
    clock: &Clock,
    ctx: &mut TxContext,
): Armour {
    cap.consume_action(clock);
    assert!(ingots.value() == ARMOUR_INGOT_COST, EWrongIngotAmount);
    forge.ingot_treasury.burn(ingots);
    let armour = Armour { id: object::new(ctx), ingots_used: ARMOUR_INGOT_COST };
    event::emit(ArmourSmithed { player: cap.player(), armour_id: armour.id.to_inner() });
    armour
}

/// The frontend calls these wrappers: delivery to `cap.player()` happens
/// inside Move, so the NFT lands in the REAL wallet in the same
/// session-signed transaction — no client can misdirect it.
entry fun smith_weapon_and_keep(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ingots: Coin<INGOT>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let weapon = smith_weapon(forge, cap, ingots, clock, ctx);
    transfer::public_transfer(weapon, cap.player());
}

entry fun smith_armour_and_keep(
    forge: &mut Forge,
    cap: &mut SessionCap,
    ingots: Coin<INGOT>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let armour = smith_armour(forge, cap, ingots, clock, ctx);
    transfer::public_transfer(armour, cap.player());
}

// === Test hooks ===

/// `mine` is untestable from a `_tests` module (non-public entry), so give
/// tests a same-module wrapper plus deterministic coin faucets.
#[test_only]
public fun mine_for_testing(
    forge: &mut Forge,
    cap: &mut SessionCap,
    r: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    mine(forge, cap, r, clock, ctx);
}

#[test_only]
public fun mint_ore_for_testing(
    forge: &mut Forge,
    amount: u64,
    ctx: &mut TxContext,
): Coin<ORE> {
    forge.ore_treasury.mint(amount, ctx)
}

#[test_only]
public fun mint_ingots_for_testing(
    forge: &mut Forge,
    amount: u64,
    ctx: &mut TxContext,
): Coin<INGOT> {
    forge.ingot_treasury.mint(amount, ctx)
}
