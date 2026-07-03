import { createWalletAdapter } from '@builders-of-stuff/svelte-sui-wallet-adapter';

import { NETWORK } from './config';

export const walletAdapter = createWalletAdapter({
  network: NETWORK,
  storageKey: 'ore-forge:wallet',
  slushWallet: { name: 'Ore Forge' },
});
