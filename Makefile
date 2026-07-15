# EvilAgent – zkratky pro časté operace
.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help build up down restart logs ps shell root-shell attach \
        tools update backup restore health

help: ## Zobrazí tuto nápovědu
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	 | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Postaví image
	$(COMPOSE) build

up: ## Spustí kontejner na pozadí
	$(COMPOSE) up -d

down: ## Zastaví a odstraní kontejner (volumes ZŮSTANOU)
	$(COMPOSE) down

restart: ## Restartuje kontejner
	$(COMPOSE) restart

logs: ## Sleduje logy
	$(COMPOSE) logs -f

ps: ## Stav kontejneru
	$(COMPOSE) ps

shell: ## Interaktivní shell jako uživatel 'agent'
	$(COMPOSE) exec -u agent evilagent bash -l

root-shell: ## Shell jako root (správa, apt, ...)
	$(COMPOSE) exec -u root evilagent bash -l

attach: ## Připojí se ke sdílenému tmux 'main'
	$(COMPOSE) exec -u agent evilagent tmux attach -t main

tools: ## Vypíše stav nainstalovaných nástrojů
	$(COMPOSE) exec -u root evilagent /usr/local/lib/evilagent/install-tools.sh

update: ## Aktualizuje vše (rebuild + refresh nástrojů), data zůstanou
	./scripts/update.sh

backup: ## Záloha dat agentů do backups/
	./scripts/backup.sh

health: ## Zdravotní stav kontejneru
	$(COMPOSE) exec -u agent evilagent bash -lc 'for t in codex claude agy hermes openclaw agent2telegram agentsmon; do command -v $$t >/dev/null && echo "OK   $$t" || echo "MISS $$t"; done'
