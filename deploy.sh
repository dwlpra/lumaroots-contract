#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== LumaRoots Deployment Script ===${NC}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${RED}Error: .env file not found!${NC}"
    echo "Please copy .env.example to .env and fill in your PRIVATE_KEY"
    exit 1
fi

# Load environment variables
source .env

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}Error: PRIVATE_KEY not set in .env!${NC}"
    echo "Please add your deployer wallet private key"
    exit 1
fi

echo -e "${YELLOW}Deploying to Mantle Sepolia...${NC}"
echo ""

# Build contracts first
echo "Building contracts..."
forge build

if [ $? -ne 0 ]; then
    echo -e "${RED}Build failed!${NC}"
    exit 1
fi

# Deploy
echo ""
echo "Deploying contracts..."
forge script script/Deploy.s.sol:DeployLumaRoots \
    --rpc-url $MANTLE_SEPOLIA_RPC \
    --broadcast \
    -vvvv

if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}=== Deployment Successful! ===${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Copy the contract addresses from above"
    echo "2. Update .env with LUMAROOTS_ADDRESS and MOCK_PRICE_FEED_ADDRESS"
    echo "3. Update frontend and backend config files"
else
    echo -e "${RED}Deployment failed!${NC}"
    exit 1
fi
