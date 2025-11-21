#!/bin/bash
# Start ComfyUI in sandbox user environment

set -e

# Configuration
SANDBOX_USER="comfyui_sandbox"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting ComfyUI in sandbox environment${NC}"
echo -e "${YELLOW}   User: ${SANDBOX_USER}${NC}"
echo ""

# Check if sandbox user exists
if ! dscl . -read /Users/${SANDBOX_USER} &>/dev/null; then
    echo -e "${YELLOW}⚠️  Sandbox user not found!${NC}"
    echo "   Run provisioning first:"
    echo "   make provision"
    exit 1
fi

# Check if ComfyUI is installed
if [ ! -d "/Users/${SANDBOX_USER}/ComfyUI" ]; then
    echo -e "${YELLOW}⚠️  ComfyUI not found in sandbox!${NC}"
    echo "   Run provisioning first:"
    echo "   cd ${PROJECT_DIR}"
    echo "   make provision"
    exit 1
fi

echo -e "${GREEN}✅ Sandbox environment ready${NC}"
echo ""
echo -e "${BLUE}Starting ComfyUI...${NC}"
echo "   Access UI at: http://127.0.0.1:8188"
echo "   Press Ctrl+C to stop"
echo ""

# Switch to sandbox user and run ComfyUI
# Using sudo -u instead of su for better automation
sudo -u ${SANDBOX_USER} -i bash << 'EOF'
cd ~/ComfyUI
source venv/bin/activate
python main.py --listen 127.0.0.1 --port 8188
EOF
