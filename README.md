# LumaRoots Smart Contracts

Smart contracts for LumaRoots - A Web3 tree planting platform.

## Contracts

### `LumaRoots.sol`
Main contract for tree purchases and NFT certificates.
- Handles tree purchases with native token payments
- Mints NFT certificates for planted trees
- Integrates with price oracle for EUR conversion
- Tracks user tree ownership and planting records
- Watering game for engagement (separate from purchases)

### `RootsToken.sol`
ERC20 utility token for rewards and gamification (optional/future).

## Setup

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js 18+

### Installation

```bash
# Install dependencies
forge install

# Compile contracts
forge build

# Run tests
forge test
```

## Deployment

### Testnet

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## Contract Addresses

| Contract | Network | Address |
|----------|---------|---------|
| LumaRoots | Mantle Sepolia | TBD |
| MockPriceFeed | Mantle Sepolia | TBD |

## License

MIT
