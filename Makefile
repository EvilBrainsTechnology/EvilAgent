# EvilAgent – shortcuts for common operations
.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help build up down restart logs ps shell root-shell attach \
        tools update backup restore health

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

ps: ## Show container status
	$(COMPOSE) ps

shell: ## Interactive shell as user 'agent'
	$(COMPOSE) exec -u agent evilagent bash -l

root-shell: ## Shell as root (system administration, apt, ...)
	$(COMPOSE) exec -u root evilagent bash -l

attach: ## Attach to the shared tmux session 'main'
	$(COMPOSE) exec -u agent evilagent tmux attach -t main

tools: ## Reinstall / update all agent CLI tools
	$(COMPOSE) exec -u root evilagent /usr/local/lib/evilagent/install-tools.sh

update: ## Full update (rebuild + tool refresh), data is preserved
	./scripts/update.sh

backup: ## Back up agent data to backups/
	./scripts/backup.sh

health: ## Check which tools are installed
	$(COMPOSE) exec -u agent evilagent bash -lc 'for t in codex claude agy hermes openclaw agent2telegram agentsmon; do command -v $$t >/dev/null && echo "OK   $$t" || echo "MISS $$t"; done'
