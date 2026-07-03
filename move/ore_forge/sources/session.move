/// Hand-rolled session keys (the SessionCap pattern).
///
/// The browser generates an ephemeral keypair; the real wallet signs ONE
/// transaction that mints a `SessionCap` scoped to the sender's player and
/// transfers it to the ephemeral address. From then on the ephemeral key
/// signs every in-game action silently — no wallet popup per click.
///
/// Ownership IS the auth layer: session-gated functions never check
/// `ctx.sender()` — the runtime already guarantees only the cap's owner can
/// pass it. The cap's `player` field says whose state to mutate.
///
/// Defense layers on the stolen-key scenario: (1) expiry against the Clock,
/// (2) a decrementing action budget, (3) the cap only gates non-extractive
/// verbs — anything that mints or moves assets demands the real wallet.
module ore_forge::session;

use sui::clock::Clock;
use sui::event;

#[error]
const ESessionExpired: vector<u8> = b"Session has expired";
#[error]
const ENoActionsLeft: vector<u8> = b"Session action budget is exhausted";

/// `key`-only (no `store`): the cap cannot be wrapped, listed on a Kiosk, or
/// moved by generic transfer functions — sessions can never become a
/// tradeable commodity, and only this module decides where a cap goes.
public struct SessionCap has key {
    id: UID,
    /// The real wallet whose player state this session may mutate.
    player: address,
    expires_at_ms: u64,
    actions_left: u64,
}

public struct SessionMinted has copy, drop {
    cap_id: ID,
    player: address,
    session_address: address,
    expires_at_ms: u64,
    actions: u64,
}

public struct SessionRevoked has copy, drop {
    cap_id: ID,
    player: address,
}

/// Signed once by the real wallet: mints a cap scoped to the sender's player
/// and hands it to the ephemeral session address. The cap is `key`-only so
/// the transfer must happen here, not in the calling PTB.
///
/// `ttl_ms == 0` means the session never expires; `actions == 0` means the
/// action budget is unlimited. Both encode as u64::MAX so `consume_action`
/// needs no special cases. A forever-session lives until `revoke`.
public fun mint(
    session_address: address,
    ttl_ms: u64,
    actions: u64,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    let expires_at_ms = if (ttl_ms == 0) {
        std::u64::max_value!()
    } else {
        clock.timestamp_ms() + ttl_ms
    };
    let actions_left = if (actions == 0) std::u64::max_value!() else actions;
    let cap = SessionCap {
        id: object::new(ctx),
        player: ctx.sender(),
        expires_at_ms,
        actions_left,
    };
    event::emit(SessionMinted {
        cap_id: cap.id.to_inner(),
        player: cap.player,
        session_address,
        expires_at_ms,
        actions: actions_left,
    });
    transfer::transfer(cap, session_address);
}

/// Revocation = destroying the cap (owner-initiated). Expiry handles the
/// rest; no shared revocation registry, so gameplay stays fully parallel.
public fun revoke(cap: SessionCap) {
    let SessionCap { id, player, .. } = cap;
    event::emit(SessionRevoked { cap_id: id.to_inner(), player });
    id.delete();
}

/// Validate and spend one action. Called by every session-gated verb.
public(package) fun consume_action(cap: &mut SessionCap, clock: &Clock) {
    assert!(clock.timestamp_ms() < cap.expires_at_ms, ESessionExpired);
    assert!(cap.actions_left > 0, ENoActionsLeft);
    cap.actions_left = cap.actions_left - 1;
}

public fun player(cap: &SessionCap): address { cap.player }

public fun expires_at_ms(cap: &SessionCap): u64 { cap.expires_at_ms }

public fun actions_left(cap: &SessionCap): u64 { cap.actions_left }
