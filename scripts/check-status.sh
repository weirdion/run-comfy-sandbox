#!/bin/bash
# Check status of sandbox environment and ComfyUI

set -e

SANDBOX_USER="comfyui_sandbox"
SANDBOX_HOME="/Users/${SANDBOX_USER}"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📊 ComfyUI Sandbox Status${NC}"
echo ""

# Check if user exists
echo -n "Sandbox user (${SANDBOX_USER}): "
if dscl . -read /Users/${SANDBOX_USER} &>/dev/null; then
    echo -e "${GREEN}✅ exists${NC}"

    # Get UID
    UID=$(dscl . -read /Users/${SANDBOX_USER} UniqueID | awk '{print $2}')
    echo "   UID: $UID"
    echo "   Home: $SANDBOX_HOME"
else
    echo -e "${RED}❌ not found${NC}"
    echo ""
    echo "Run: ansible-playbook ansible/playbook.yml"
    exit 1
fi

echo ""

# Check if ComfyUI is installed
echo -n "ComfyUI installation: "
if [ -d "${SANDBOX_HOME}/ComfyUI" ]; then
    echo -e "${GREEN}✅ installed${NC}"
    echo "   Path: ${SANDBOX_HOME}/ComfyUI"

    # Check venv
    if [ -f "${SANDBOX_HOME}/ComfyUI/venv/bin/activate" ]; then
        echo -e "   Venv: ${GREEN}✅ ready${NC}"
    else
        echo -e "   Venv: ${RED}❌ missing${NC}"
    fi

    # Count custom nodes
    if [ -d "${SANDBOX_HOME}/ComfyUI/custom_nodes" ]; then
        NODE_COUNT=$(ls -1 "${SANDBOX_HOME}/ComfyUI/custom_nodes" 2>/dev/null | wc -l | xargs)
        echo "   Custom nodes: $NODE_COUNT"
    fi
else
    echo -e "${RED}❌ not found${NC}"
fi

echo ""

# Check if running
echo -n "ComfyUI process: "
PIDS=$(pgrep -u ${SANDBOX_USER} -f "python.*main.py" 2>/dev/null || true)
if [ -n "$PIDS" ]; then
    echo -e "${GREEN}✅ running${NC}"
    echo "   PIDs: $PIDS"
    echo "   URL: http://127.0.0.1:8188"
else
    echo -e "${YELLOW}⏸️  not running${NC}"
fi

echo ""

# Check shared directory
echo -n "Shared directory: "
SHARED_DIR="${HOME}/comfyui_shared"
if [ -d "$SHARED_DIR" ]; then
    echo -e "${GREEN}✅ exists${NC}"
    echo "   Path: $SHARED_DIR"
    echo "   Size: $(du -sh "$SHARED_DIR" 2>/dev/null | cut -f1)"
else
    echo -e "${YELLOW}⚠️  not found${NC}"
fi

echo ""

# Check model symlinks
echo "Model symlinks:"
if [ -d "${SANDBOX_HOME}/ComfyUI/models" ]; then
    for dir in checkpoints loras vae embeddings controlnet; do
        if [ -L "${SANDBOX_HOME}/ComfyUI/models/$dir" ]; then
            TARGET=$(readlink "${SANDBOX_HOME}/ComfyUI/models/$dir")
            echo -e "   $dir: ${GREEN}✅${NC} -> $TARGET"
        elif [ -d "${SANDBOX_HOME}/ComfyUI/models/$dir" ]; then
            echo -e "   $dir: ${YELLOW}📁 directory (not symlink)${NC}"
        else
            echo -e "   $dir: ${RED}❌ missing${NC}"
        fi
    done
else
    echo -e "   ${RED}Models directory not found${NC}"
fi

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
