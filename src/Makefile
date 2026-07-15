# EvilAgent – shortcuts for common operations
.DEFAULT_GOAL := help
COMPOSE := docker compose
SERVICE := evilagent

.PHONY: help build up down restart logs ps shell root-shell attach \
        tools update backup restore health agents lint

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	 | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the image
	$(COMPOSE) build

up: ## Start the container in the background
	$(COMPOSE) up -d

down: ## Stop and remove the container (volumes are KEPT)
	$(COMPOSE) down

restart: ## Restart the container
	$(COMPOSE) restart

logs: ## Follow container logs
	$(COMPOSE) logs -f

agents: ## Show agent status (AgentsMonitor)
	$(COMPOSE) exec -u agent $(SERVICE) bash -lc 'agentsmon status'

ps: ## Show container status
	$(COMPOSE) ps

shell: ## Interactive shell as user 'agent'
	$(COMPOSE) exec -u agent $(SERVICE) bash -l

root-shell: ## Shell as root (system administration, apt, ...)
	$(COMPOSE) exec -u root $(SERVICE) bash -l

attach: ## Attach to the shared tmux session 'main'
	$(COMPOSE) exec -u agent $(SERVICE) tmux attach -t main

tools: ## Temporarily reinstall tools in the running container
	$(COMPOSE) exec -u root $(SERVICE) /usr/local/lib/evilagent/install-tools.sh

update: ## Full update (backup + rebuild), data is preserved
	./scripts/update.sh

backup: ## Back up agent data to src/backups/
	./scripts/backup.sh

health: ## Verify enabled tools run (respects INSTALL_* flags)
	$(COMPOSE) exec -u agent $(SERVICE) /usr/local/bin/evilagent-health

lint: ## Run shellcheck + hadolint locally (same checks as CI)
	shellcheck scripts/*.sh
	hadolint Dockerfile
	$(COMPOSE) config -q
