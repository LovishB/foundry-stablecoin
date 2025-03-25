# Decentralized Stablecoin (DSC)

A decentralized, algorithmic stablecoin pegged to the US Dollar, built on the Ethereum blockchain using Solidity and the Foundry framework.

## Overview

This project implements a decentralized stablecoin system inspired by DAI but with several important differences:
- No governance mechanism
- No fees
- Collateralized only by WETH (Wrapped Ethereum)
- Maintained at a 1:1 peg with USD through algorithmic mechanisms
- Always overcollateralized

## Key Features

- **200% Collateralization Ratio**: Ensures the system remains solvent even during market volatility
- **Exogenous Collateral**: Uses WETH as its collateral asset
- **Chainlink Price Feeds**: Utilizes Chainlink oracles for accurate ETH/USD price data
- **Liquidation Mechanism**: Allows external actors to liquidate undercollateralized positions with a 10% bonus incentive
- **Reentrancy Protection**: Implements OpenZeppelin's ReentrancyGuard for secure function execution

## System Architecture

The system consists of two main contracts:

1. **DecentralizedStableCoin.sol**: ERC20 token implementation with mint and burn functionality
2. **DSCEngine.sol**: Core logic contract that handles all collateral and stablecoin operations

## Key Functions

### DSCEngine

- `depositCollateral`: Deposit WETH as collateral
- `mintDSC`: Mint DSC tokens against deposited collateral
- `depositCollateralAndMintDsc`: Perform both actions in a single transaction
- `redeemCollateral`: Withdraw collateral (if health factor remains adequate)
- `burnDSC`: Burn DSC tokens to reduce debt position
- `redeemCollateralAndBurnDSC`: Perform both actions in a single transaction
- `liquidate`: Allow external users to liquidate unhealthy positions

### DecentralizedStableCoin

- `mint`: Create new DSC tokens (restricted to owner/engine)
- `burn`: Destroy DSC tokens (restricted to owner/engine)

## Health Factor System

The protocol uses a health factor system to ensure adequate collateralization:

- **Health Factor ≥ 4**: Required for all minting and redemption operations (200% collateralization)
- **Health Factor < 3**: Position becomes eligible for liquidation (below 150% collateralization)

## Liquidation Process

1. External liquidator identifies an undercollateralized position (health factor < 3)
2. Liquidator calls `liquidate()` with the amount of debt they want to cover
3. Liquidator receives the equivalent collateral value plus a 10% bonus
4. User's position is updated accordingly

## Installation and Setup

### Prerequisites

- [Git](https://git-scm.com/)
- [Foundry](https://book.getfoundry.sh/getting-started/installation)

### Clone the Repository

```bash
git clone https://github.com/your-username/decentralized-stablecoin.git
cd decentralized-stablecoin
```

### Install Dependencies

```bash
forge install
```

### Compile Contracts

```bash
forge build
```

### Run Tests

```bash
forge test
```

## Usage Examples

Here are some examples of how to interact with the system (using Foundry's `cast` tool):

### Deposit Collateral

```bash
cast send --private-key $PRIVATE_KEY $DSC_ENGINE_ADDRESS "depositCollateral(address,uint256)" $WETH_ADDRESS $AMOUNT_IN_WEI
```

### Mint Stablecoin

```bash
cast send --private-key $PRIVATE_KEY $DSC_ENGINE_ADDRESS "mintDSC(uint256)" $AMOUNT_IN_WEI
```

## Security Considerations

- The system is designed to be always overcollateralized
- Chainlink price feeds are used for secure price discovery
- ReentrancyGuard protects against reentrancy attacks
- Error handling is comprehensive with specific error messages

## Future Improvements

- Add support for additional collateral types beyond WETH
- Implement a DAO for governance decisions
- Create an interest rate model for borrowing
- Develop a front-end interface for easier interaction

## License

This project is licensed under the UNLICENSED License - see the LICENSE file for details.

## Author

Lovish Badlani

## Acknowledgments

- Inspired by MakerDAO's DAI stablecoin
- Built using OpenZeppelin contracts
- Uses Chainlink price feeds for oracle data
