#[test_only]
module ore_forge::forge_tests;

use ore_forge::forge::{Self, World};
use ore_forge::session::{Self, SessionCap};
use std::unit_test::assert_eq;
use sui::clock;
use sui::random::{Self, Random};
use sui::test_scenario::{Self as ts, Scenario};

const PLAYER: address = @0xA;
const SESSION_ADDRESS: address = @0x5E5;

const HOUR_MS: u64 = 60 * 60 * 1000;

/// init world + player, then mint a session cap for SESSION_ADDRESS.
fun setup(ttl_ms: u64, actions: u64): Scenario {
    let mut scenario = ts::begin(PLAYER);
    forge::init_for_testing(scenario.ctx());

    scenario.next_tx(PLAYER);
    let mut world = scenario.take_shared<World>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::create_player(&mut world, scenario.ctx());
    session::mint(SESSION_ADDRESS, ttl_ms, actions, &clock, scenario.ctx());
    ts::return_shared(world);
    clock.destroy_for_testing();

    scenario
}

#[test]
fun full_loop_smelts_and_smiths() {
    let mut scenario = setup(HOUR_MS, 10);

    // Deterministic ore (mining randomness is covered separately).
    scenario.next_tx(PLAYER);
    let mut world = scenario.take_shared<World>();
    forge::add_ore_for_testing(&mut world, PLAYER, 7);
    ts::return_shared(world);

    // The ephemeral session key does everything without the real wallet:
    // smelts twice (7 ore -> 1 ore + 2 ingots), then smiths a weapon NFT.
    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::smelt(&mut world, &mut cap, &clock);
    forge::smelt(&mut world, &mut cap, &clock);
    let (ore, ingots, _, _) = forge::player_stats(&world, PLAYER);
    assert_eq!(ore, 1);
    assert_eq!(ingots, 2);
    let weapon = forge::smith_weapon(&mut world, &mut cap, &clock, scenario.ctx());
    let (_, ingots, weapons, _) = forge::player_stats(&world, PLAYER);
    assert_eq!(ingots, 0);
    assert_eq!(weapons, 1);
    assert_eq!(cap.actions_left(), 7);
    // The NFT goes to the real player, never to the ephemeral signer.
    transfer::public_transfer(weapon, cap.player());
    scenario.return_to_sender(cap);
    ts::return_shared(world);
    clock.destroy_for_testing();

    // Verify the weapon landed in the player's wallet.
    scenario.next_tx(PLAYER);
    let weapon = scenario.take_from_sender<forge::Weapon>();
    scenario.return_to_sender(weapon);

    scenario.end();
}

#[test]
fun mine_yields_ore_within_bounds() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let random = scenario.take_shared<Random>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::mine_for_testing(&mut world, &mut cap, &random, &clock, scenario.ctx());
    let (ore, _, _, _) = forge::player_stats(&world, PLAYER);
    assert!(ore >= 1 && ore <= 3);
    assert_eq!(cap.actions_left(), 9);
    scenario.return_to_sender(cap);
    ts::return_shared(world);
    ts::return_shared(random);
    clock.destroy_for_testing();

    scenario.end();
}

#[test, expected_failure(abort_code = forge::ENotEnoughOre, location = forge)]
fun smelt_aborts_without_enough_ore() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::smelt(&mut world, &mut cap, &clock);
    abort
}

#[test, expected_failure(abort_code = forge::ENotEnoughIngots, location = forge)]
fun smith_aborts_without_enough_ingots() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    let weapon = forge::smith_weapon(&mut world, &mut cap, &clock, scenario.ctx());
    transfer::public_transfer(weapon, PLAYER);
    abort
}

#[test, expected_failure(abort_code = session::ESessionExpired, location = session)]
fun expired_session_cannot_act() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(HOUR_MS + 1);
    forge::smelt(&mut world, &mut cap, &clock);
    abort
}

#[test, expected_failure(abort_code = session::ENoActionsLeft, location = session)]
fun exhausted_session_cannot_act() {
    let mut scenario = setup(HOUR_MS, 1);

    scenario.next_tx(PLAYER);
    let mut world = scenario.take_shared<World>();
    forge::add_ore_for_testing(&mut world, PLAYER, 6);
    ts::return_shared(world);

    scenario.next_tx(SESSION_ADDRESS);
    let mut world = scenario.take_shared<World>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::smelt(&mut world, &mut cap, &clock);
    forge::smelt(&mut world, &mut cap, &clock);
    abort
}

#[test, expected_failure(abort_code = forge::EPlayerAlreadyExists, location = forge)]
fun duplicate_player_aborts() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(PLAYER);
    let mut world = scenario.take_shared<World>();
    forge::create_player(&mut world, scenario.ctx());
    abort
}
