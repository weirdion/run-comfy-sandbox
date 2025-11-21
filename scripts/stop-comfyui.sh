#!/bin/bash
# Stop ComfyUI running in sandbox

set -e

SANDBOX_USER="comfyui_sandbox"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🛑 Stopping ComfyUI...${NC}"

# Find and kill ComfyUI processes for sandbox user
PIDS=$(pgrep -u ${SANDBOX_USER} -f "python.*main.py" || true)

if [ -z "$PIDS" ]; then
    echo -e "${GREEN}✅ No ComfyUI processes found${NC}"
    exit 0
fi

echo "   Found processes: $PIDS"

# Graceful shutdown
for PID in $PIDS; do
    echo "   Stopping PID $PID..."
    sudo kill $PID || true
done

# Wait a bit
sleep 2

# Force kill if still running
REMAINING=$(pgrep -u ${SANDBOX_USER} -f "python.*main.py" || true)
if [ -n "$REMAINING" ]; then
    echo "   Force stopping remaining processes..."
    sudo pkill -9 -u ${SANDBOX_USER} -f "python.*main.py" || true
fi

echo -e "${GREEN}✅ ComfyUI stopped${NC}"
