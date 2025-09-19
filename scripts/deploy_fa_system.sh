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
aptos move compile --profile $PROFILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Compilation successful${NC}"
else
    echo -e "${RED}❌ Compilation failed${NC}"
    exit 1
fi

# Run tests
echo -e "${YELLOW}🧪 Running tests...${NC}"
aptos move test --profile $PROFILE

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed${NC}"
else
    echo -e "${RED}❌ Tests failed${NC}"
    exit 1
fi

# Deploy the contracts
echo -e "${YELLOW}🚢 Deploying contracts to ${NETWORK}...${NC}"
aptos move publish --profile $PROFILE --assume-yes

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful${NC}"
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi

# Get the deployed address
DEPLOYED_ADDRESS=$(aptos config show-profiles --profile $PROFILE | grep account | awk '{print $2}')
echo -e "${BLUE}Deployed address: ${DEPLOYED_ADDRESS}${NC}"

# Initialize the TinyPay FA system
echo -e "${YELLOW}⚙️  Initializing TinyPay FA system...${NC}"
aptos move run \
    --function-id "${DEPLOYED_ADDRESS}::tinypay::init_system" \
    --profile $PROFILE \
    --assume-yes

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ TinyPay FA system initialized${NC}"
else
    echo -e "${RED}❌ System initialization failed${NC}"
    exit 1
fi

# Initialize USDC FA for testing
echo -e "${YELLOW}💱 Initializing test USDC FA...${NC}"
aptos move run \
    --function-id "${DEPLOYED_ADDRESS}::usdc::init_module" \
    --profile $PROFILE \
    --assume-yes

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Test USDC FA initialized${NC}"
else
    echo -e "${RED}❌ USDC FA initialization failed${NC}"
fi

# Get USDC metadata address
echo -e "${YELLOW}🔍 Getting USDC metadata address...${NC}"
USDC_METADATA=$(aptos move view \
    --function-id "${DEPLOYED_ADDRESS}::usdc::get_metadata" \
    --profile $PROFILE | jq -r '.[]')

echo -e "${BLUE}USDC Metadata Address: ${USDC_METADATA}${NC}"

# Add USDC support to TinyPay
echo -e "${YELLOW}🔗 Adding USDC support to TinyPay...${NC}"
aptos move run \
    --function-id "${DEPLOYED_ADDRESS}::tinypay::add_asset_support" \
    --args "object:${USDC_METADATA}" \
    --profile $PROFILE \
    --assume-yes

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ USDC support added to TinyPay${NC}"
else
    echo -e "${RED}❌ Failed to add USDC support${NC}"
fi

# Verify deployment
echo -e "${YELLOW}✅ Verifying deployment...${NC}"
IS_SUPPORTED=$(aptos move view \
    --function-id "${DEPLOYED_ADDRESS}::tinypay::is_asset_supported" \
    --args "object:${USDC_METADATA}" \
    --profile $PROFILE | jq -r '.[]')

if [ "$IS_SUPPORTED" = "true" ]; then
    echo -e "${GREEN}✅ USDC is supported in TinyPay${NC}"
else
    echo -e "${RED}❌ USDC support verification failed${NC}"
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
echo -e "   aptos move run --function-id ${DEPLOYED_ADDRESS}::tinypay::deposit --args object:${USDC_METADATA} u64:100000 \"vector<u8>:0x696e697469616c5f7461696c\" --profile $PROFILE"
echo -e "\n3. Check your balance:"
echo -e "   aptos move view --function-id ${DEPLOYED_ADDRESS}::tinypay::get_balance --args address:<your_address> object:${USDC_METADATA} --profile $PROFILE"
echo -e "\n${YELLOW}For more examples, check: examples/fa_usage_demo.md${NC}"

echo -e "\n${GREEN}Happy using TinyPay FA! 🚀${NC}"
