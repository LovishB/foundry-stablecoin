-include .env

.PHONY: all deploy-sepolia deploy-mainnet

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy-mainnet - Deploy to Ethereum Mainnet"
	@echo "  make deploy-sepolia - Deploy to Sepolia network"
	@echo "  make deploy-local - Deploy to Anvil local"

# Deploy to Mainnet
deploy-mainnet:
	@forge script script/DeployDSC.s.sol:DeployDSC \
	--rpc-url $(MAINNET_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	-vvvv

# Deploy to Sepolia
deploy-sepolia:
	@forge script script/DeployDSC.s.sol:DeployDSC \
	--rpc-url $(SEPOLIA_RPC_URL) \
	--private-key $(PRIVATE_KEY) \
	--broadcast \
	--verify \
	-vvvv


# Local deployment
deploy-local:
	@forge script script/DeployDSC.s.sol:DeployDSC \
	--rpc-url http://localhost:8545 \
	--private-key $(DEFAULT_ANVIL_KEY) \
	--broadcast