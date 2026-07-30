# lmstack — local LLM stack for development.
#
# Most people should not need this file: install the skill and ask it for a
# starting point. These targets are the explicit path underneath.
#
# Targets arrive with their implementation, one phase at a time (see PLAN.md).
# Host lifecycle lands in Phase 1, skill-install in Phase 3, pi-install in
# Phase 4, docs in Phase 5.

SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@echo "lmstack — targets:"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ---------------------------------------------------------------------------
# Tests — none of these need a host or a GPU
# ---------------------------------------------------------------------------

.PHONY: test
test: validate validator-test redaction-test render-test lint ## Run the full offline suite (T0, T1)

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

.PHONY: lint
lint: ## yamllint, shellcheck, ansible-lint, playbook syntax (T0.1, T0.2)
	@./tests/lint.sh

# ---------------------------------------------------------------------------
# Observability
# ---------------------------------------------------------------------------

.PHONY: stacklog
stacklog: ## Pretty-print the local host change log
	@cat .stacklog/*.jsonl 2>/dev/null \
		| jq -r '"\(.ts)  \(.host)  \(.status|ascii_upcase)  \(.action)"' \
		|| echo "no .stacklog entries yet"
