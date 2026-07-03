/// ORE — the raw mining resource, a real fungible Coin visible in wallets.
module ore_forge::ore;

use sui::coin;
use sui::url;

/// Update after re-hosting the icon (e.g. Walrus); wallets need a public URL.
const ICON_URL: vector<u8> =
    b"https://raw.githubusercontent.com/Neuradite-Games/ore-forge/main/app/static/items/ore.svg";

public struct ORE has drop {}

/// `create_currency` is deprecated in favor of `coin_registry`, but the
/// registry flow needs an extra post-publish finalization step — the classic
/// API keeps the manual deploy simple. Migration noted in PROJECT.md.
#[allow(deprecated_usage)]
fun init(otw: ORE, ctx: &mut TxContext) {
    let (treasury, metadata) = coin::create_currency(
        otw,
        0, // whole ore only
        b"ORE",
        b"Ore",
        b"Raw ore mined in Ore Forge. Smelt 3 into an ingot.",
        option::some(url::new_unsafe_from_bytes(ICON_URL)),
        ctx,
    );
    transfer::public_freeze_object(metadata);
    // The publisher hands this to forge::create_forge right after publish.
    transfer::public_transfer(treasury, ctx.sender());
}
