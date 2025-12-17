.PHONY: help provision teardown start start-expose stop status shell check update-nodes update-nodes-pull update-comfyui update-all rollback-nodes

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# Base workspace directory
WORKSPACE_DIR := ~/workspace/ai

help: ## Show this help message
	@echo "$(BLUE)ComfyUI Sandbox Management$(NC)"
	@echo ""
	@echo "$(GREEN)Available commands:$(NC)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(BLUE)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)First time setup:$(NC)"
	@echo "  1. make provision         # Create sandbox environment"
	@echo "  2. make start             # Start ComfyUI"
	@echo ""
	@echo "$(YELLOW)Update workflows:$(NC)"
	@echo "  make update-nodes         # Add new nodes from config"
	@echo "  make update-nodes-pull    # Update all nodes to latest"
	@echo "  make update-comfyui       # Update ComfyUI core"
	@echo "  make update-all           # Update everything"
	@echo ""
	@echo "$(YELLOW)Rollback:$(NC)"
	@echo "  make rollback-nodes       # Rollback nodes to previous version"
	@echo ""

check-ansible: ## Check if Ansible is installed
	@command -v ansible-playbook >/dev/null 2>&1 || { echo "$(YELLOW)Ansible not found.$(NC)"; exit 1; }

provision: check-ansible ## Provision the sandbox environment
	@echo "$(BLUE)Provisioning ComfyUI sandbox...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml playbook.yml --ask-become-pass

update-nodes: check-ansible ## Sync custom nodes (add new, keep existing)
	@echo "$(BLUE)Syncing custom nodes...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml update-nodes.yml --ask-become-pass

update-nodes-pull: check-ansible ## Update all custom nodes to latest (git pull)
	@echo "$(BLUE)Pulling latest changes for all custom nodes...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml update-nodes.yml -e "update_mode=pull" --ask-become-pass

update-comfyui: check-ansible ## Update ComfyUI itself to latest version
	@echo "$(BLUE)Updating ComfyUI core...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml update-comfyui.yml --ask-become-pass

update-all: check-ansible ## Update ComfyUI and all custom nodes
	@echo "$(BLUE)Updating everything...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml update-comfyui.yml --ask-become-pass
	cd ansible && ansible-playbook -i inventory.yml update-nodes.yml -e "update_mode=both" --ask-become-pass

rollback-nodes: check-ansible ## Rollback custom nodes to previous version
	@echo "$(YELLOW)Rolling back custom nodes...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml rollback-nodes.yml --ask-become-pass

teardown: check-ansible ## Completely remove sandbox environment
	@echo "$(YELLOW)⚠️  This will remove the sandbox environment$(NC)"
	cd ansible && ansible-playbook -i inventory.yml teardown.yml --ask-become-pass

start: ## Start ComfyUI in sandbox (localhost only)
	@bash scripts/start-comfyui.sh

start-expose: ## Start ComfyUI accessible from network (0.0.0.0)
	@COMFYUI_LISTEN_HOST=0.0.0.0 bash scripts/start-comfyui.sh

comfyui-start: start ## Alias for start

stop: ## Stop ComfyUI
	@bash scripts/stop-comfyui.sh

comfyui-stop: stop ## Alias for stop

status: ## Check sandbox and ComfyUI status
	@bash scripts/check-status.sh

shell: ## Open shell as sandbox user
	@bash scripts/shell-sandbox.sh

comfyui-shell: shell ## Alias for shell

check: status ## Alias for status

logs: ## Show recent ComfyUI logs (if running)
	@echo "$(BLUE)Recent ComfyUI activity...$(NC)"
	@sudo -u comfyui_sandbox tail -n 50 /Users/comfyui_sandbox/ComfyUI/*.log 2>/dev/null || echo "No logs found"

fix-permissions: ## Fix group permissions on shared directories (after adding models/files)
	@echo "$(BLUE)Fixing permissions on shared directories...$(NC)"
	@# Fix external drive models (if it's a symlink, fix the target)
	@if [ -L "$(WORKSPACE_DIR)/models" ]; then \
		MODELS_TARGET=$$(readlink $(WORKSPACE_DIR)/models); \
		echo "$(YELLOW)Models is a symlink to: $$MODELS_TARGET$(NC)"; \
		sudo chgrp -R comfyshared "$$MODELS_TARGET"; \
		sudo chown -R "$$USER:comfyshared" "$$MODELS_TARGET"; \
		sudo chmod -R 775 "$$MODELS_TARGET"; \
	else \
		sudo chgrp -R comfyshared $(WORKSPACE_DIR)/models; \
		sudo chown -R "$$USER:comfyshared" $(WORKSPACE_DIR)/models; \
		sudo chmod -R 775 $(WORKSPACE_DIR)/models; \
	fi
	@sudo chgrp -R comfyshared $(WORKSPACE_DIR)/comfy/workflows
	@sudo chgrp -R comfyshared $(WORKSPACE_DIR)/input
	@sudo chgrp -R comfyshared $(WORKSPACE_DIR)/output
	@sudo chown -R "$$USER:comfyshared" $(WORKSPACE_DIR)/comfy/workflows
	@sudo chown -R "$$USER:comfyshared" $(WORKSPACE_DIR)/input
	@sudo chown -R "$$USER:comfyshared" $(WORKSPACE_DIR)/output
	@sudo chmod -R 775 $(WORKSPACE_DIR)/comfy/workflows
	@sudo chmod -R 775 $(WORKSPACE_DIR)/input
	@sudo chmod -R 775 $(WORKSPACE_DIR)/output
	@echo "$(GREEN)✓ Permissions fixed$(NC)"

update-volumes: check-ansible ## Update shared volumes configuration only
	@echo "$(BLUE)Updating shared volumes...$(NC)"
	cd ansible && ansible-playbook -i inventory.yml playbook.yml --tags volumes --ask-become-pass
	@echo "$(GREEN)✓ Volumes updated$(NC)"
