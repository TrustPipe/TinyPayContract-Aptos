#!/bin/bash

# TinyPay FA System Deployment Script
# This script helps deploy and initialize the TinyPay FA system

set -e

echo "🚀 Starting TinyPay FA System Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NETWORK=${1:-testnet}
PROFILE=${2:-default}

echo -e "${BLUE}Network: ${NETWORK}${NC}"
echo -e "${BLUE}Profile: ${PROFILE}${NC}"

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}Error: $1 is not installed${NC}"
        exit 1
    fi
}

# Check dependencies
echo -e "${YELLOW}Checking dependencies...${NC}"
check_command aptos
check_command jq

# Compile the contracts
echo -e "${YELLOW}📦 Compiling contracts...${NC}"
aptos move compile --dev --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Compilation successful${NC}"
else
    echo -e "${RED}❌ Compilation failed${NC}"
    exit 1
fi

# Run tests
echo -e "${YELLOW}🧪 Running tests...${NC}"
aptos move test --dev --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed${NC}"
else
    echo -e "${RED}❌ Tests failed${NC}"
    exit 1
fi

# Get the deployer address first
DEPLOYED_ADDRESS=$(aptos config show-profiles --profile $PROFILE | grep account | awk '{print $2}' | tr -d '",')
echo -e "${BLUE}Deployer address: ${DEPLOYED_ADDRESS}${NC}"

# Update Move.toml with the deployer address before deployment
echo -e "${YELLOW}📝 Updating Move.toml with deployer address...${NC}"
sed -i.bak "s/tinypay = \"_\"/tinypay = \"${DEPLOYED_ADDRESS}\"/" Move.toml
# Also update dev-addresses to match
sed -i.bak2 "s/tinypay = \"0x[a-fA-F0-9]*\"/tinypay = \"${DEPLOYED_ADDRESS}\"/" Move.toml

# Recompile with the correct address
echo -e "${YELLOW}📦 Recompiling with deployer address...${NC}"
aptos move compile --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Recompilation successful${NC}"
else
    echo -e "${RED}❌ Recompilation failed${NC}"
    # Restore original Move.toml
    mv Move.toml.bak Move.toml
    exit 1
fi

# Deploy the contracts
echo -e "${YELLOW}🚢 Deploying contracts to ${NETWORK}...${NC}"
aptos move publish --profile $PROFILE --assume-yes --skip-fetch-latest-git-deps

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful${NC}"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    # Restore original Move.toml
    mv Move.toml.bak Move.toml
    exit 1
fi

# Note: TinyPay FA system and USDC FA are automatically initialized during deployment
echo -e "${GREEN}✅ TinyPay FA system and USDC FA automatically initialized during deployment${NC}"

# Wait a moment for deployment to settle
echo -e "${YELLOW}⏳ Waiting for deployment to settle...${NC}"
sleep 3

# Get USDC metadata address
echo -e "${YELLOW}🔍 Getting USDC metadata address...${NC}"
USDC_METADATA=$(aptos move view \
    --function-id "${DEPLOYED_ADDRESS}::usdc::get_metadata" \
    --profile $PROFILE | jq -r '.Result[0].inner')

if [ -z "$USDC_METADATA" ] || [ "$USDC_METADATA" = "null" ]; then
    echo -e "${RED}❌ Failed to get USDC metadata address${NC}"
    exit 1
fi

echo -e "${BLUE}USDC Metadata Address: ${USDC_METADATA}${NC}"

# Check if USDC is already supported
echo -e "${YELLOW}🔍 Checking if USDC is already supported...${NC}"
IS_ALREADY_SUPPORTED=$(aptos move view \
    --function-id "${DEPLOYED_ADDRESS}::tinypay::is_asset_supported" \
    --args "address:${USDC_METADATA}" \
    --profile $PROFILE | jq -r '.Result[0]')

if [ "$IS_ALREADY_SUPPORTED" = "true" ]; then
    echo -e "${GREEN}✅ USDC support already exists${NC}"
else
    # Add USDC support to TinyPay
    echo -e "${YELLOW}🔗 Adding USDC support to TinyPay...${NC}"
    aptos move run \
        --function-id "${DEPLOYED_ADDRESS}::tinypay::add_asset_support" \
        --args "address:${USDC_METADATA}" \
        --profile $PROFILE \
        --assume-yes

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ USDC support added to TinyPay${NC}"
    else
        echo -e "${RED}❌ Failed to add USDC support${NC}"
        exit 1
    fi
fi

# Verify deployment
echo -e "${YELLOW}✅ Verifying deployment...${NC}"
IS_SUPPORTED=$(aptos move view \
    --function-id "${DEPLOYED_ADDRESS}::tinypay::is_asset_supported" \
    --args "address:${USDC_METADATA}" \
    --profile $PROFILE | jq -r '.Result[0]')

if [ "$IS_SUPPORTED" = "true" ]; then
    echo -e "${GREEN}✅ USDC is supported in TinyPay${NC}"
else
    echo -e "${RED}❌ USDC support verification failed${NC}"
    exit 1
fi

# Display summary
echo -e "\n${GREEN}🎉 Deployment Complete!${NC}\n"
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo -e "Network: ${NETWORK}"
echo -e "Profile: ${PROFILE}"
echo -e "Contract Address: ${DEPLOYED_ADDRESS}"
echo -e "USDC Metadata: ${USDC_METADATA}"
echo -e "\n${BLUE}=== Next Steps ===${NC}"
echo -e "1. Mint some test USDC:"
echo -e "   aptos move run --function-id ${DEPLOYED_ADDRESS}::usdc::mint --args address:<your_address> u64:1000000 --profile $PROFILE"
echo -e "\n2. Deposit USDC to TinyPay:"
echo -e "   aptos move run --function-id ${DEPLOYED_ADDRESS}::tinypay::deposit --args address:${USDC_METADATA} u64:100000 \"vector<u8>:0x696e697469616c5f7461696c\" --profile $PROFILE"
echo -e "\n3. Check your balance:"
echo -e "   aptos move view --function-id ${DEPLOYED_ADDRESS}::tinypay::get_balance --args address:<your_address> address:${USDC_METADATA} --profile $PROFILE"
echo -e "\n${YELLOW}For more examples, check: examples/fa_usage_demo.md${NC}"

echo -e "\n${GREEN}Happy using TinyPay FA! 🚀${NC}"

# Restore original Move.toml
if [ -f Move.toml.bak ]; then
    mv Move.toml.bak Move.toml
    echo -e "${YELLOW}📝 Restored original Move.toml${NC}"
fi
