#[test_only]
module ore_forge::forge_tests;

use ore_forge::forge::{Self, Forge, Weapon};
use ore_forge::ingot::INGOT;
use ore_forge::ore::ORE;
use ore_forge::session::{Self, SessionCap};
use std::unit_test::assert_eq;
use sui::clock;
use sui::coin::{Self, Coin};
use sui::random::{Self, Random};
use sui::test_scenario::{Self as ts, Scenario};

const PLAYER: address = @0xA;
const SESSION_ADDRESS: address = @0x5E5;

const HOUR_MS: u64 = 60 * 60 * 1000;

/// Share a Forge (with test treasuries) and mint a session cap for
/// SESSION_ADDRESS on PLAYER's behalf.
fun setup(ttl_ms: u64, actions: u64): Scenario {
    let mut scenario = ts::begin(PLAYER);
    forge::create_forge(
        coin::create_treasury_cap_for_testing<ORE>(scenario.ctx()),
        coin::create_treasury_cap_for_testing<INGOT>(scenario.ctx()),
        scenario.ctx(),
    );

    scenario.next_tx(PLAYER);
    let clock = clock::create_for_testing(scenario.ctx());
    session::mint(SESSION_ADDRESS, ttl_ms, actions, &clock, scenario.ctx());
    clock.destroy_for_testing();

    scenario
}

#[test]
fun full_loop_smelts_and_smiths() {
    let mut scenario = setup(HOUR_MS, 10);

    // The ephemeral session key does everything: smelt 6 ore into 2 ingots,
    // then smith a weapon NFT — all without the real wallet.
    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());

    let mut ore = forge.mint_ore_for_testing(6, scenario.ctx());
    let batch = ore.split(3, scenario.ctx());
    let mut ingots = forge.smelt(&mut cap, batch, &clock, scenario.ctx());
    let more_ingots = forge.smelt(&mut cap, ore, &clock, scenario.ctx());
    ingots.join(more_ingots);
    assert_eq!(ingots.value(), 2);

    let weapon = forge.smith_weapon(&mut cap, ingots, &clock, scenario.ctx());
    assert_eq!(cap.actions_left(), 7);
    // The NFT goes to the real player, never to the ephemeral signer.
    transfer::public_transfer(weapon, cap.player());

    scenario.return_to_sender(cap);
    ts::return_shared(forge);
    clock.destroy_for_testing();

    // Verify the weapon landed in the player's wallet.
    scenario.next_tx(PLAYER);
    let weapon = scenario.take_from_sender<Weapon>();
    scenario.return_to_sender(weapon);

    scenario.end();
}

#[test]
fun mine_delivers_ore_coins_to_session() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(@0x0);
    random::create_for_testing(scenario.ctx());

    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let random = scenario.take_shared<Random>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    forge::mine_for_testing(&mut forge, &mut cap, &random, &clock, scenario.ctx());
    assert_eq!(cap.actions_left(), 9);
    scenario.return_to_sender(cap);
    ts::return_shared(forge);
    ts::return_shared(random);
    clock.destroy_for_testing();

    // The minted ORE is a real coin owned by the session address.
    scenario.next_tx(SESSION_ADDRESS);
    let ore = scenario.take_from_sender<Coin<ORE>>();
    assert!(ore.value() >= 1 && ore.value() <= 3);
    scenario.return_to_sender(ore);

    scenario.end();
}

#[test, expected_failure(abort_code = forge::EWrongOreAmount, location = forge)]
fun smelt_aborts_on_wrong_ore_amount() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    let ore = forge.mint_ore_for_testing(2, scenario.ctx());
    let ingot = forge.smelt(&mut cap, ore, &clock, scenario.ctx());
    transfer::public_transfer(ingot, PLAYER);
    abort
}

#[test, expected_failure(abort_code = forge::EWrongIngotAmount, location = forge)]
fun smith_aborts_on_wrong_ingot_amount() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    let ingots = forge.mint_ingots_for_testing(1, scenario.ctx());
    let weapon = forge.smith_weapon(&mut cap, ingots, &clock, scenario.ctx());
    transfer::public_transfer(weapon, PLAYER);
    abort
}

#[test, expected_failure(abort_code = session::ESessionExpired, location = session)]
fun expired_session_cannot_act() {
    let mut scenario = setup(HOUR_MS, 10);

    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(HOUR_MS + 1);
    let ore = forge.mint_ore_for_testing(3, scenario.ctx());
    let ingot = forge.smelt(&mut cap, ore, &clock, scenario.ctx());
    transfer::public_transfer(ingot, PLAYER);
    abort
}

#[test, expected_failure(abort_code = session::ENoActionsLeft, location = session)]
fun exhausted_session_cannot_act() {
    let mut scenario = setup(HOUR_MS, 1);

    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let clock = clock::create_for_testing(scenario.ctx());
    let ore = forge.mint_ore_for_testing(3, scenario.ctx());
    let ingot = forge.smelt(&mut cap, ore, &clock, scenario.ctx());
    transfer::public_transfer(ingot, PLAYER);
    let more_ore = forge.mint_ore_for_testing(3, scenario.ctx());
    let ingot = forge.smelt(&mut cap, more_ore, &clock, scenario.ctx());
    transfer::public_transfer(ingot, PLAYER);
    abort
}

#[test]
fun forever_session_survives_time_and_exhaustion() {
    // ttl 0 = never expires, actions 0 = unlimited.
    let mut scenario = setup(0, 0);

    // Ten years later the same cap still works.
    scenario.next_tx(SESSION_ADDRESS);
    let mut forge = scenario.take_shared<Forge>();
    let mut cap = scenario.take_from_sender<SessionCap>();
    let mut clock = clock::create_for_testing(scenario.ctx());
    clock.set_for_testing(10 * 365 * 24 * HOUR_MS);
    let ore = forge.mint_ore_for_testing(3, scenario.ctx());
    let ingots = forge.smelt(&mut cap, ore, &clock, scenario.ctx());
    assert_eq!(ingots.value(), 1);
    transfer::public_transfer(ingots, cap.player());
    scenario.return_to_sender(cap);
    ts::return_shared(forge);
    clock.destroy_for_testing();

    // Manual close is the only way out: revoke destroys the cap.
    scenario.next_tx(SESSION_ADDRESS);
    let cap = scenario.take_from_sender<SessionCap>();
    session::revoke(cap);

    scenario.end();
}
