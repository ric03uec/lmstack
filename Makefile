# lmstack — local LLM stack for development.
#
# Most people should not need this file: install the skill and ask it for a
# starting point. These targets are the explicit path underneath.
#
# Targets arrive with their implementation, one phase at a time (see PLAN.md).

SHELL := /bin/bash
.DEFAULT_GOAL := help

INVENTORY := inventory/hosts.ini
ANSIBLE   := ansible-playbook -i $(INVENTORY)

.PHONY: help
help: ## Show this help
	@echo "lmstack — targets:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Host targets need HOST=, e.g.  make up HOST=h1-nvidia"

# ---------------------------------------------------------------------------
# Tests — none of these need a host or a GPU
# ---------------------------------------------------------------------------

.PHONY: test
test: validate validator-test redaction-test render-test classify-test skill-install-test pi-config-test lint ## Run the full offline suite (T0, T1, T4.1, T4.6, T6.1-T6.3)

.PHONY: validate
validate: ## Validate host and model configuration (T0.3-T0.13)
	@python3 tests/validate_models.py

.PHONY: validator-test
validator-test: ## Prove the validator rejects known-bad configuration
	@./tests/validator_test.sh

.PHONY: redaction-test
redaction-test: ## Prove .stacklog never records secrets (T0.12)
	@./tests/redaction_test.sh

.PHONY: render-test
render-test: ## Render every host's templates and assert the invariants (T1)
	@./tests/render_test.sh

.PHONY: classify-test
classify-test: ## Classify every probe fixture and assert the verdict (T6.1, T6.2)
	@./tests/probe_classify_test.sh

.PHONY: skill-install-test
skill-install-test: ## Prove the install binds an absolute repo path (T6.3)
	@./tests/skill_install_test.sh

.PHONY: pi-config-test
pi-config-test: ## Prove the pi sync copies extensions and merges (T4.1, T4.6)
	@./tests/pi_config_test.sh

.PHONY: lint
lint: ## yamllint, shellcheck, ansible-lint, playbook syntax (T0.1, T0.2)
	@./tests/lint.sh

# ---------------------------------------------------------------------------
# Skill
# ---------------------------------------------------------------------------

.PHONY: skill-install
skill-install: ## Install the lmstack skill (AGENT=claude|opencode|pi for one)
	@skills/install.sh $(if $(AGENT),--agent $(AGENT),)

.PHONY: skill-list
skill-list: ## Show where the skill would be installed, without writing
	@skills/install.sh --list

# ---------------------------------------------------------------------------
# Control host
# ---------------------------------------------------------------------------

.PHONY: pi-install
pi-install: ## Merge the lmstack pi configuration into ~/.pi/agent
	@pi-config/sync.sh install

.PHONY: pi-dump
pi-dump: ## Capture control-host changes back into pi-config/
	@pi-config/sync.sh dump

# ---------------------------------------------------------------------------
# Host lifecycle
# ---------------------------------------------------------------------------

.PHONY: guard-host
guard-host:
	@if [ -z "$(HOST)" ]; then \
		echo "error: HOST is required, e.g. make $(MAKECMDGOALS) HOST=h1-nvidia"; \
		echo "available:"; ls -1 hosts | sed 's/^/  /'; exit 1; \
	fi
	@if [ ! -d "hosts/$(HOST)" ]; then \
		echo "error: no such host 'hosts/$(HOST)'"; exit 1; \
	fi
	@if [ ! -f "$(INVENTORY)" ]; then \
		echo "error: $(INVENTORY) not found — cp inventory/hosts.ini.example $(INVENTORY)"; exit 1; \
	fi

.PHONY: deps
deps: ## Install the Ansible collections the playbooks need
	@ansible-galaxy collection install -r requirements.yml

.PHONY: bootstrap
bootstrap: guard-host ## Install Docker + GPU runtime + firewall on HOST
	$(ANSIBLE) hosts/$(HOST)/ansible/00-bootstrap.yml -l $(HOST)

.PHONY: up
up: validate guard-host ## Render, pull, start, and health-gate the stack on HOST
	$(ANSIBLE) hosts/$(HOST)/ansible/10-stack.yml -l $(HOST)

.PHONY: verify
verify: guard-host ## Run the endpoint conformance suite against HOST
	$(ANSIBLE) hosts/$(HOST)/ansible/20-verify.yml -l $(HOST)

.PHONY: site
site: validate guard-host ## bootstrap + up + verify in one run
	$(ANSIBLE) hosts/$(HOST)/ansible/site.yml -l $(HOST)

.PHONY: check
check: guard-host ## Dry-run the full playbook against HOST (--check --diff)
	$(ANSIBLE) hosts/$(HOST)/ansible/site.yml -l $(HOST) --check --diff

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

.PHONY: stacklog
stacklog: ## Pretty-print the local host change log
	@cat .stacklog/*.jsonl 2>/dev/null \
		| jq -r '"\(.ts)  \(.host)  \(.status|ascii_upcase)  \(.action)"' \
		|| echo "no .stacklog entries yet"

# ---------------------------------------------------------------------------
# Documentation
# ---------------------------------------------------------------------------

# npm ci needs the lockfile; the first run on a clone has no node_modules.
website/node_modules: website/package-lock.json
	@cd website && npm ci
	@touch website/node_modules

.PHONY: docs
docs: website/node_modules ## Serve the documentation site with hot reload
	@cd website && npm start

.PHONY: docs-build
docs-build: website/node_modules ## Build the static site; fails on a broken link
	@cd website && npm run build
