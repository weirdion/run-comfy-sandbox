# ComfyUI Sandbox Environment

Secure, isolated environment for running ComfyUI on macOS with full GPU access using a separate user account managed by Ansible.

## 🎯 Why This Exists

Based on LLM security review, several ComfyUI custom nodes contain critical vulnerabilities including:
- Arbitrary code execution (eval, pickle deserialization)
- Command injection
- Path traversal attacks
- Unsafe file operations

This sandbox provides **isolation without sacrificing GPU performance** - something container based soltions cannot provide on macOS easily.

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  Primary User (my_user)          │
│  - Your normal account                  │
│  - Runs browser to access UI            │
│  - Manages sandbox via Ansible          │
│  - Owns models (read-only to sandbox)   │
└─────────────────────────────────────────┘
                    │
                    │ Ansible manages
                    ▼
┌─────────────────────────────────────────┐
│  Sandbox User (comfyui_sandbox)         │
│  - Isolated user account                │
│  - Runs ComfyUI process                 │
│  - Cannot access primary user files     │
│  - Full Metal GPU access (MPS)          │
│  - Localhost-only network               │
└─────────────────────────────────────────┘
```

### What's Protected

✅ **File System Isolation**
- Sandbox user cannot read/write your personal files
- Cannot access SSH keys, credentials, Documents, etc.
- Runs in separate home directory
- Shared directories use Unix group permissions (no ACLs needed)

✅ **Full GPU Performance**
- Direct Metal Performance Shaders (MPS) access
- No virtualization overhead
- Same performance as running natively

✅ **Network Isolation**
- ComfyUI bound to localhost only (127.0.0.1)
- No external network exposure
- Browser connects via localhost


## 📁 Project Structure

```
run-comfy-sandbox/
├── ansible/
│   ├── playbook.yml              # Main provisioning playbook
│   ├── teardown.yml              # Complete removal playbook
│   ├── inventory.yml             # Localhost configuration
│   ├── udpate-comfy.yml          # update ComfyUI
│   ├── udpate-nodes.yml          # update all custom nodes
│   ├── rollback-nodes.yml        # use .sandbox-version to revert last update pull
│   ├── vars/
│   │   └── main.yml             # Configuration variables
│   └── roles/
│       ├── sandbox-user/        # User creation
│       ├── comfyui-setup/       # ComfyUI installation
│       ├── custom-nodes/        # ComfyUI nodes clone and requirement install
│       └── shared-volumes/      # Model symlinks, shared dirs
├── scripts/
│   ├── start-comfyui.sh         # Start ComfyUI
│   ├── stop-comfyui.sh          # Stop ComfyUI
│   ├── shell-sandbox.sh         # Open sandbox shell
│   └── check-status.sh          # Check environment status
├── Makefile                      # Convenience commands
└── README.md                     # This file
```

## 🚀 Quick Start

### 1. Install Ansible (one time)

```bash
brew install ansible
```

### 2. Provision Sandbox Environment

```bash
cd run-comfy-sandbox
make provision
```

This will:
- Create sandbox user (`comfyui_sandbox`)
- Create shared group (`comfyshared`) with both personal and sandbox users
- Clone and set up ComfyUI
- Create Python virtual environment
- Install dependencies with GPU support
- Set up shared directories with group permissions
- Symlink input, workflow, model, and output directories (2775 permissions)
- Clone custom nodes from git repositories

**You'll be prompted for:**
- Your sudo password (to create user)
- Sandbox user password

### 3. Start ComfyUI

```bash
make start
```

Then open your browser: http://localhost:8188

### 4. Stop ComfyUI

```bash
# In another terminal
make stop

# Or just Ctrl+C in the running terminal
```

## 📋 Available Commands

```bash
make help              # Show all commands
make provision         # Create/update sandbox environment
make start            # Start ComfyUI
make stop             # Stop ComfyUI
make status           # Check status
make shell            # Open shell as sandbox user
make teardown         # Completely remove sandbox
```

## ⚙️ Configuration

Edit [`ansible/vars/main.yml`](ansible/vars/main.yml) to customize:

### Sandbox User & Shared Group

```yaml
sandbox_user: comfyui_sandbox
sandbox_user_uid: 503
sandbox_user_shell: /bin/zsh

# Shared group for file access
shared_group: comfyshared
shared_group_gid: 504
```

Both your primary user and the sandbox user are members of the `comfyshared` group, allowing controlled file sharing.

### ComfyUI Settings

```yaml
comfyui_repo: "https://github.com/comfyanonymous/ComfyUI.git"
comfyui_branch: "master"
comfyui_listen_host: "127.0.0.1"  # Localhost only!
comfyui_port: 8188
```

## 🔧 Common Tasks

### Check Sandbox Status

```bash
make status
```

Shows:
- Sandbox user status
- ComfyUI installation status
- Running processes
- Shared directory info
- Model symlink status

### Open Shell in Sandbox

```bash
make shell
# Now you're the sandbox user
```

### Add More Custom Nodes

1. **Security review first!** (See initial security report)
2. Add to `custom_nodes` list in `ansible/vars/main.yml`:

```yaml
custom_nodes:
  - name: ComfyUI-YourNode
    repo: https://github.com/user/ComfyUI-YourNode.git
    enabled: true
```

3. Re-run provisioning:

```bash
make provision
# or just update nodes:
cd ansible && ansible-playbook -i inventory.yml playbook.yml --tags nodes --ask-become-pass
```
