#!/bin/bash
# Open an interactive shell as the sandbox user

set -e

SANDBOX_USER="comfyui_sandbox"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${BLUE}🐚 Opening shell as ${SANDBOX_USER}${NC}"
echo -e "${GREEN}   Type 'exit' to return to your primary user${NC}"
echo ""

# Switch to sandbox user with interactive shell
sudo -u ${SANDBOX_USER} -i
