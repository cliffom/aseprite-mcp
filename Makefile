# Development tasks for aseprite-mcp. `make` with no target lists them.
#
# Python runs through Poetry, in a project-local .venv — nothing is installed
# into the global interpreter. Poetry 2 reads the PEP 621 [project] table
# directly, so pyproject.toml needs no Poetry-specific sections.

POETRY ?= poetry
LUA    ?= lua

# Forces the venv into ./.venv rather than Poetry's shared cache dir, without
# touching the developer's global Poetry config.
export POETRY_VIRTUALENVS_IN_PROJECT := true

RUN := $(POETRY) run

.DEFAULT_GOAL := help

.PHONY: help install test test-py test-lua build install-plugin run \
        check-versions clean distclean

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

install: ## Create .venv and install the package with dev extras
	$(POETRY) install --extras dev

test: test-py test-lua ## Run both test suites

test-py: ## Run the server tests (pytest)
	$(RUN) pytest

test-lua: ## Run the plugin tests (needs Lua 5.4 on PATH)
	@command -v $(LUA) >/dev/null 2>&1 || { \
		echo "$(LUA) not found — install Lua 5.4 (brew install lua / apt install lua5.4 / winget install DEVCOM.Lua)"; \
		exit 1; }
	$(LUA) tests/lua/run.lua

build: ## Build dist/aseprite-mcp.aseprite-extension
	$(RUN) python scripts/build_extension.py

install-plugin: ## Build and install the extension into Aseprite (restart Aseprite after)
	$(RUN) python scripts/install_plugin.py

run: ## Run the MCP server on stdio (normally started by an MCP client)
	$(RUN) aseprite-mcp

check-versions: ## Verify pyproject.toml, package.json and PLUGIN_VER agree
	@py=$$(sed -n 's/^version = "\(.*\)"/\1/p' pyproject.toml); \
	pkg=$$(sed -n 's/.*"version": *"\(.*\)".*/\1/p' plugin/package.json); \
	lua=$$(sed -n 's/^local PLUGIN_VER *= *"\(.*\)".*/\1/p' plugin/main.lua); \
	echo "pyproject.toml  $$py"; \
	echo "package.json    $$pkg"; \
	echo "PLUGIN_VER      $$lua"; \
	if [ "$$py" = "$$pkg" ] && [ "$$py" = "$$lua" ]; then echo "ok"; \
	else echo "version mismatch"; exit 1; fi

clean: ## Remove build artefacts and caches
	rm -rf build dist .pytest_cache *.egg-info
	find . -name __pycache__ -type d -not -path './.venv/*' -prune -exec rm -rf {} +

distclean: clean ## Also remove the .venv
	rm -rf .venv
