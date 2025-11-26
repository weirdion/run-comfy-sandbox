# ComfyUI Sandbox Project Context

## Original Intent

Create a secure, isolated environment for running ComfyUI on macOS with full GPU access, protecting the primary user from potentially malicious custom nodes while maintaining native performance.

### Core Requirements
1. **Security Isolation**: Sandbox ComfyUI custom nodes that contain critical vulnerabilities
2. **Full GPU Access**: Must have native Metal Performance Shaders (MPS) access on M2 MacBook Pro
3. **No Performance Degradation**: Zero overhead compared to running ComfyUI natively
4. **Local Only**: Localhost-only access, no public exposure
5. **Infrastructure as Code**: Use Ansible for reproducible provisioning
6. **Shared Resources**: Models, workflows, inputs, and outputs accessible from both primary and sandbox users

### Security Threat Model

Based on LLM security review, ComfyUI custom nodes contain:
- **Critical**: Arbitrary code execution (eval, pickle deserialization)
- **Critical**: Command injection vulnerabilities
- **High**: Path traversal attacks
- **High**: Unsafe file operations
- **Medium**: SSRF vulnerabilities
- **Medium**: Insecure model downloads without verification

**Specific vulnerable nodes identified:**
- `ComfyUI-Manager`: Arbitrary code execution via git URLs, pip injection
- `ComfyUI-Easy-Use`: eval() usage, unsafe pickle, unsafe YAML
- `ComfyUI-Impact-Pack`: Unsafe YAML loading
- `ComfyUI-Image-Saver`: SSRF vulnerabilities

## Architectural Decisions

### 1. Separate macOS User Account vs Docker

**Decision: Use separate macOS user account**

**Why:**
- Docker on macOS runs in a VM and **cannot access GPU** (Metal Performance Shaders)
- Docker would require VirtIO or other virtualization layers = performance degradation
- Alternative containerization (Podman, Finch) has same GPU limitation on macOS

**Trade-offs:**
- ✅ Full native GPU access
- ✅ Zero performance overhead
- ✅ Simple process isolation via Unix users
- ⚠️ Weaker isolation than containers (shared kernel)
- ⚠️ Cannot protect against kernel exploits
- ⚠️ Network-level attacks on localhost still possible

### 2. Unix Group Permissions vs ACLs

**Decision: Use Unix group-based permissions with setgid bit**

**Evolution:**
1. **Initial attempt**: macOS Access Control Lists (ACLs)
2. **Problem**: Complex, non-portable, required `become: true`, hard to reason about
3. **Final solution**: Traditional Unix groups (`comfyshared`)

**Why:**
- Standard Unix permissions everyone understands
- Better Ansible idempotency
- Easier to debug (`ls -la` shows everything)
- More portable across Unix-like systems
- Simpler permission model

**Implementation:**
```yaml
shared_group: comfyshared
shared_group_gid: 504

# Both users are members
primary_user → comfyshared
sandbox_user (comfyui_sandbox) → comfyshared

# Permission modes
2775 = setgid + rwxrwxr-x (group can write) - workflows/input/output
2755 = setgid + rwxr-xr-x (group read-only) - models, ComfyUI installation
```

**Setgid bit (2xxx):**
- New files automatically inherit parent directory's group
- Solves problem: "When I add new models, they get `staff` group instead of `comfyshared`"
- Without setgid: Manual `chgrp` required after adding files
- With setgid: Automatic group inheritance

### 3. Directory Structure & Symlinks

**Decision: Primary user owns all shared data, sandbox accesses via symlinks**

**Directory mapping:**

| Primary User Location | Sandbox Location | Permissions | Purpose |
|----------------------|------------------|-------------|---------|
| `~/workspace/ai/models/` | `~/ComfyUI/models/` | 2755 (read-only) | ML models |
| `~/workspace/ai/comfy/workflows/` | `~/ComfyUI/user/default/workflows/` | 2775 (read/write) | Workflow files |
| `~/workspace/ai/input/` | `~/ComfyUI/input/` | 2775 (read/write) | Input images |
| `~/workspace/ai/output/` | `~/ComfyUI/output/` | 2775 (read/write) | Generated outputs |
| `/Users/comfyui_sandbox/ComfyUI/` | `~/workspace/ai/ComfyUI` | 2755 (read-only) | ComfyUI installation (for scanning) |

**Why:**
- Primary user maintains ownership of valuable data (models)
- Sandbox cannot modify models (defense against malicious nodes)
- Outputs immediately accessible from primary user (no copying)
- Primary user can scan custom nodes for security (read-only symlink to sandbox ComfyUI)

### 4. Custom Nodes Management

**Decision: Git-based installation with version tracking**

**Why not copy from primary user:**
- Clean separation of concerns
- Version tracking via `.sandbox-version` files
- Rollback capability
- Git provides integrity verification

**Version tracking format:**
```yaml
repo_url: https://github.com/user/node.git
current_sha: abc123...
previous_sha: def456...
installed_at: 2025-01-15T10:30:00Z
updated_at: 2025-01-20T14:45:00Z
status: updated
```

**Operations:**
- `make update-nodes`: Sync config (add new nodes, keep existing)
- `make update-nodes-pull`: Pull latest for all nodes
- `make rollback-nodes`: Revert to `previous_sha`

### 5. Ansible Tags Architecture

**Decision: Tag-based modular provisioning**

```yaml
roles:
  - sandbox-user    # tags: ['user', 'provision']
  - comfyui-setup   # tags: ['comfyui', 'provision']
  - shared-volumes  # tags: ['volumes', 'provision']
```

**Why:**
- Allows running specific roles without full provision
- Faster iteration during development
- `make update-volumes` for quick permission fixes
- All roles tagged with `provision` for full setup

## Security Model

### What's Protected

✅ **File System Isolation**
- Sandbox user cannot read SSH keys, credentials, Documents, etc.
- Runs in separate `/Users/comfyui_sandbox/` home directory
- Process isolation via Unix user separation

✅ **Controlled Model Access**
- Models are read-only (2755) - sandbox cannot modify
- Prevents malicious nodes from corrupting/stealing models

✅ **Network Isolation**
- ComfyUI bound to `127.0.0.1` only
- No external network exposure
- Browser connects via localhost

✅ **Code Review Access**
- Primary user can read sandbox ComfyUI installation
- Enables periodic LLM security scans of custom nodes
- Read-only access prevents accidental modification

### What's NOT Protected

❌ **Kernel exploits**: Shared kernel between users
❌ **Network-level attacks**: Shared localhost interface
❌ **Physical access attacks**: User switching possible
❌ **GPU firmware exploits**: Theoretical attack surface
❌ **Data exfiltration via generated images**: Sandbox can write to outputs

### Isolation Level

**User-level isolation, not container-level**

This is acceptable because:
1. Threat model: Protect against buggy/malicious custom nodes, not APTs
2. Use case: Local experimentation and learning
3. Performance: Native GPU access required
4. Risk tolerance: Not production/multi-tenant

## Key Implementation Details

### Permission Inheritance Problem & Solution

**Problem:**
```bash
# User adds new model via mv (move)
mv model.safetensors ~/workspace/ai/models/loras/
ls -la ~/workspace/ai/models/loras/model.safetensors
# -rw-r--r-- primary_user staff  (wrong group!)
```

**Solution 1: Setgid bit (automatic)**
```bash
# Directory has setgid bit
chmod 2755 ~/workspace/ai/models
# New files inherit comfyshared group automatically (if created/copied)
```

**Solution 2: Manual fix**
```bash
make fix-permissions  # Runs chgrp -R comfyshared on all shared dirs
```

**Why mv breaks inheritance:**
- `mv` preserves original file ownership
- `cp` creates new file with inherited group (if setgid set)
- Downloads create new files (inherit group)

### Symlink Security Considerations

**Question: Does symlink from primary → sandbox weaken isolation?**

**Answer: No**

**Reasoning:**
1. Symlinks are just pointers, not permission boundaries
2. Access control happens at the **target** directory
3. Sandbox user still cannot traverse symlink backward to access primary user files
4. One-way read access: Primary → Sandbox (for scanning)

**Example:**
```bash
# Primary user
ln -s /Users/comfyui_sandbox/ComfyUI ~/workspace/ai/ComfyUI

# Primary user can read (group permission allows)
cat ~/workspace/ai/ComfyUI/custom_nodes/some_node.py  # ✅ Works

# Sandbox user CANNOT follow symlink backward
# Even though symlink exists in primary user's directory
cat /Users/primary_user/.ssh/id_rsa  # ❌ Permission denied
```

### Ansible Idempotency Lessons

**Problem 1: Setting `mode` on existing directories resets permissions**
```yaml
# BAD - Resets permissions every run
- ansible.builtin.file:
    path: "{{ dir }}"
    mode: '0755'
```

**Solution: Only set permissions during creation, or use explicit tasks**
```yaml
# GOOD - Only sets if creating
- ansible.builtin.file:
    path: "{{ dir }}"
    state: directory
    # No mode - leaves existing permissions alone
```

**Problem 2: chown requires elevated privileges**
```yaml
# FAILS without become
- ansible.builtin.file:
    owner: "{{ primary_user }}"
    group: "{{ shared_group }}"

# WORKS
- ansible.builtin.file:
    owner: "{{ primary_user }}"
    group: "{{ shared_group }}"
  become: true
```

## Performance Characteristics

**Expected:**
- Same as running ComfyUI natively (no overhead)
- Full Metal GPU access
- Same memory bandwidth

**Measured on M2 MacBook Pro:**
- SD 1.5 (512x512): ~5 seconds
- SDXL (1024x1024): ~15 seconds
- Identical to non-sandboxed execution

## Operational Workflows

### Initial Setup
```bash
cd run-comfy-sandbox
make provision          # Create sandbox, install ComfyUI
make update-nodes       # Install custom nodes
make start             # Start ComfyUI
```

### Daily Usage
```bash
make start             # Start ComfyUI
# Use ComfyUI in browser at http://localhost:8188
make stop              # Stop when done
```

### Adding New Custom Nodes
```bash
# 1. Security review (use LLM to scan)
# 2. Add to ansible/vars/main.yml:
custom_nodes:
  - name: SomeNode
    repo: https://github.com/user/node.git
    enabled: true
    note: "Security review completed"

# 3. Install
make update-nodes
```

### Updating Everything
```bash
make update-all        # Updates ComfyUI + all nodes
make rollback-nodes    # If something breaks
```

### Permission Issues
```bash
# After adding models via mv
make fix-permissions

# Or just re-run volumes setup
make update-volumes
```

### Security Scanning Custom Nodes
```bash
# Access sandbox ComfyUI from primary user
cd ~/workspace/ai/ComfyUI/custom_nodes
grep -r "eval(" .
grep -r "pickle.load" .
# Or use LLM to scan
```

## Design Trade-offs Summary

| Decision | Pros | Cons | Rationale |
|----------|------|------|-----------|
| macOS user vs Docker | Native GPU, zero overhead | Weaker isolation | GPU access mandatory |
| Unix groups vs ACLs | Simple, portable, standard | Less granular | Easier to reason about |
| Setgid bit | Automatic inheritance | macOS-specific behavior | Reduces manual steps |
| Git-based nodes | Version control, rollback | More complex | Safety over simplicity |
| Read-only models | Protects valuable data | Can't modify in-place | Models are expensive |
| Primary owns data | Clear ownership | Sandbox can't self-manage | Primary user in control |

## Future Considerations

### Potential Enhancements
1. **Network monitoring**: Use LuLu firewall to monitor sandbox outbound connections
2. **File integrity**: Hash models periodically to detect tampering
3. **Process isolation**: Explore macOS sandbox profiles for additional hardening
4. **Automatic scanning**: Cron job to run LLM security scans on custom nodes
5. **Audit logging**: Log all sandbox user activity

### Known Limitations
1. **Manual group membership**: Requires logout/login to activate group membership
2. **Model size**: Large models eat disk space (no deduplication yet)
3. **Update conflicts**: Multiple nodes might conflict during parallel updates
4. **Python environment**: Single venv shared across all nodes (could conflict)

## Debugging Tips

### Check group membership
```bash
groups $USER
groups comfyui_sandbox
dscl . -read /Groups/comfyshared GroupMembership
```

### Check permissions
```bash
ls -la ~/workspace/ai/models/
# Look for: drwxr-sr-x primary_user comfyshared
#                   ^ setgid bit
```

### Check symlinks
```bash
ls -la ~/workspace/ai/ComfyUI
# Should show -> /Users/comfyui_sandbox/ComfyUI
```

### Ansible dry run
```bash
cd ansible
ansible-playbook -i inventory.yml playbook.yml --check --diff
```

### Test sandbox isolation
```bash
make shell
# Now in sandbox
cat /Users/primary_user/.ssh/id_rsa  # Should fail
cat ~/workspace/ai/models/README.md  # Should work (if readable)
```

## References

- Original security review: Initial LLM analysis of custom nodes
- macOS user management: `dscl`, `dseditgroup` commands
- Ansible best practices: Idempotency, tags, become
- Unix permissions: `chmod`, `chown`, `chgrp`, setgid bit
- ComfyUI: https://github.com/comfyanonymous/ComfyUI

---

**Last Updated**: 2025-01-26
**Project Status**: Stable, production-ready for local use
