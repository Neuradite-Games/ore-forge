/// Ore Forge core loop: mine ore → smelt ingots at the furnace → smith
/// weapons and armour at the anvil.
///
/// Architecture (see docs/sui-reference.md §6):
/// - `World` is a shared object; per-player state lives in dynamic fields on
///   it keyed by address, so a session key can act on a player's behalf
///   (an address-owned Player object could only be touched by txs signed by
///   the real wallet).
/// - EVERY gameplay verb (`mine`, `smelt`, `smith_*`) is session-gated: one
///   wallet signature mints the SessionCap, then the ephemeral key signs the
///   whole session — including minting Weapon/Armour NFTs (they are always
///   delivered to the cap's `player`, never to the ephemeral key). A
///   production build would keep minting behind the real wallet (the
///   "tier split"); this prototype deliberately session-gates it to test
///   sign-once-play-forever.
/// - `mine` consumes on-chain randomness, so it must be a non-public `entry`
///   function (the framework blocks test-and-abort bias attacks).
module ore_forge::forge;

use ore_forge::session::SessionCap;
use sui::clock::Clock;
use sui::dynamic_field as df;
use sui::event;
use sui::random::Random;

/// Bump on incompatible World changes; ship a `migrate` in the upgrade.
const VERSION: u64 = 1;

/// Mining yields 1..=MAX_ORE_PER_MINE per swing.
const MAX_ORE_PER_MINE: u64 = 3;
/// Furnace recipe: ore in, one ingot out.
const SMELT_ORE_COST: u64 = 3;
/// Anvil recipes.
const WEAPON_INGOT_COST: u64 = 2;
const ARMOUR_INGOT_COST: u64 = 3;

#[error]
const EWrongVersion: vector<u8> = b"World version does not match this package";
#[error]
const EPlayerAlreadyExists: vector<u8> = b"Player already exists for this address";
#[error]
const ENoPlayer: vector<u8> = b"No player for this address; call create_player first";
#[error]
const ENotEnoughOre: vector<u8> = b"Not enough ore to smelt an ingot";
#[error]
const ENotEnoughIngots: vector<u8> = b"Not enough ingots to smith this item";
#[error]
const EAlreadyMigrated: vector<u8> = b"World is already at the current version";

public struct World has key {
    id: UID,
    version: u64,
    players: u64,
}

public struct AdminCap has key, store {
    id: UID,
}

/// Dynamic-field key for a player's state on the World.
public struct PlayerKey(address) has copy, drop, store;

/// Not an object — lives in a dynamic field on the World.
public struct Player has store {
    ore: u64,
    ingots: u64,
    weapons_smithed: u64,
    armour_smithed: u64,
}

/// Tradable gear: `key, store` so it composes with Kiosk / marketplaces.
public struct Weapon has key, store {
    id: UID,
    ingots_used: u64,
}

public struct Armour has key, store {
    id: UID,
    ingots_used: u64,
}

// === Events ===

public struct PlayerCreated has copy, drop {
    player: address,
}

public struct OreMined has copy, drop {
    player: address,
    amount: u64,
    ore_total: u64,
}

public struct IngotSmelted has copy, drop {
    player: address,
    ore_spent: u64,
    ingot_total: u64,
}

public struct WeaponSmithed has copy, drop {
    player: address,
    weapon_id: ID,
}

public struct ArmourSmithed has copy, drop {
    player: address,
    armour_id: ID,
}

fun init(ctx: &mut TxContext) {
    transfer::share_object(World {
        id: object::new(ctx),
        version: VERSION,
        players: 0,
    });
    transfer::public_transfer(AdminCap { id: object::new(ctx) }, ctx.sender());
}

// === Player lifecycle (real wallet) ===

public fun create_player(world: &mut World, ctx: &mut TxContext) {
    world.assert_version();
    let player = ctx.sender();
    assert!(!df::exists(&world.id, PlayerKey(player)), EPlayerAlreadyExists);
    df::add(
        &mut world.id,
        PlayerKey(player),
        Player { ore: 0, ingots: 0, weapons_smithed: 0, armour_smithed: 0 },
    );
    world.players = world.players + 1;
    event::emit(PlayerCreated { player });
}

// === Session-gated verbs (signed silently by the ephemeral key) ===

/// Swing at an ore node; yields 1..=3 ore. Non-public `entry` is mandatory:
/// this consumes `Random` at 0x8.
entry fun mine(
    world: &mut World,
    cap: &mut SessionCap,
    r: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    world.assert_version();
    cap.consume_action(clock);
    let mut gen = r.new_generator(ctx);
    let amount = gen.generate_u64_in_range(1, MAX_ORE_PER_MINE);
    let player = cap.player();
    let state = world.player_mut(player);
    state.ore = state.ore + amount;
    event::emit(OreMined { player, amount, ore_total: state.ore });
}

/// Furnace: smelt `SMELT_ORE_COST` ore into one ingot.
public fun smelt(world: &mut World, cap: &mut SessionCap, clock: &Clock) {
    world.assert_version();
    cap.consume_action(clock);
    let player = cap.player();
    let state = world.player_mut(player);
    assert!(state.ore >= SMELT_ORE_COST, ENotEnoughOre);
    state.ore = state.ore - SMELT_ORE_COST;
    state.ingots = state.ingots + 1;
    event::emit(IngotSmelted {
        player,
        ore_spent: SMELT_ORE_COST,
        ingot_total: state.ingots,
    });
}

// === Anvil: smithing (session-gated, mints NFTs to the cap's player) ===

/// Returns the Weapon; the calling PTB decides where it goes (normally a
/// transfer to `cap.player()` — the ephemeral signer never keeps assets).
public fun smith_weapon(
    world: &mut World,
    cap: &mut SessionCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Weapon {
    world.assert_version();
    cap.consume_action(clock);
    let player = cap.player();
    let state = world.player_mut(player);
    assert!(state.ingots >= WEAPON_INGOT_COST, ENotEnoughIngots);
    state.ingots = state.ingots - WEAPON_INGOT_COST;
    state.weapons_smithed = state.weapons_smithed + 1;
    let weapon = Weapon { id: object::new(ctx), ingots_used: WEAPON_INGOT_COST };
    event::emit(WeaponSmithed { player, weapon_id: weapon.id.to_inner() });
    weapon
}

public fun smith_armour(
    world: &mut World,
    cap: &mut SessionCap,
    clock: &Clock,
    ctx: &mut TxContext,
): Armour {
    world.assert_version();
    cap.consume_action(clock);
    let player = cap.player();
    let state = world.player_mut(player);
    assert!(state.ingots >= ARMOUR_INGOT_COST, ENotEnoughIngots);
    state.ingots = state.ingots - ARMOUR_INGOT_COST;
    state.armour_smithed = state.armour_smithed + 1;
    let armour = Armour { id: object::new(ctx), ingots_used: ARMOUR_INGOT_COST };
    event::emit(ArmourSmithed { player, armour_id: armour.id.to_inner() });
    armour
}

/// CLI convenience wrappers only — PTBs should call the public functions.
entry fun smith_weapon_and_keep(
    world: &mut World,
    cap: &mut SessionCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let weapon = smith_weapon(world, cap, clock, ctx);
    transfer::public_transfer(weapon, cap.player());
}

entry fun smith_armour_and_keep(
    world: &mut World,
    cap: &mut SessionCap,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let armour = smith_armour(world, cap, clock, ctx);
    transfer::public_transfer(armour, cap.player());
}

// === Views (read via simulateTransaction, or fetch the dynamic field) ===

public fun has_player(world: &World, player: address): bool {
    df::exists(&world.id, PlayerKey(player))
}

/// (ore, ingots, weapons_smithed, armour_smithed)
public fun player_stats(world: &World, player: address): (u64, u64, u64, u64) {
    assert!(df::exists(&world.id, PlayerKey(player)), ENoPlayer);
    let state: &Player = df::borrow(&world.id, PlayerKey(player));
    (state.ore, state.ingots, state.weapons_smithed, state.armour_smithed)
}

// === Admin ===

/// Forward-fix hook: bump a lagging shared World after a package upgrade.
public fun migrate(_: &AdminCap, world: &mut World) {
    assert!(world.version < VERSION, EAlreadyMigrated);
    world.version = VERSION;
}

// === Internals ===

fun assert_version(world: &World) {
    assert!(world.version == VERSION, EWrongVersion);
}

fun player_mut(world: &mut World, player: address): &mut Player {
    assert!(df::exists(&world.id, PlayerKey(player)), ENoPlayer);
    df::borrow_mut(&mut world.id, PlayerKey(player))
}

// === Test hooks ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

/// `mine` is untestable from a `_tests` module (non-public entry), so give
/// tests a same-module wrapper and a deterministic ore faucet.
#[test_only]
public fun mine_for_testing(
    world: &mut World,
    cap: &mut SessionCap,
    r: &Random,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    mine(world, cap, r, clock, ctx);
}

#[test_only]
public fun add_ore_for_testing(world: &mut World, player: address, amount: u64) {
    let state = world.player_mut(player);
    state.ore = state.ore + amount;
}
