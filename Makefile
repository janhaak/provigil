# provigil — see README.md
#
# Targets:
#   make check      syntax-check every shell script (bash -n)
#   make lint       run shellcheck (brew install shellcheck)
#   make install    run ./install.sh
#   make uninstall  run ./uninstall.sh

SHELL := /bin/bash

SCRIPTS := bin/provigil install.sh uninstall.sh

.PHONY: help check lint test install uninstall

help:
	@echo "make check      bash -n on: $(SCRIPTS)"
	@echo "make lint       shellcheck on: $(SCRIPTS)"
	@echo "make install    install the symlink and (optionally) the sudoers file"
	@echo "make uninstall  remove the symlink and the sudoers file"

# Parse-only. Never executes provigil, so it is safe on any machine.
check:
	@for f in $(SCRIPTS); do \
		printf 'bash -n %s ... ' "$$f"; \
		bash -n "$$f" && echo ok || exit 1; \
	done
	@printf 'usage/exit-code check ... '
	@rc=0; ./bin/provigil badmode >/dev/null 2>&1 || rc=$$?; \
	if [ "$$rc" -eq 1 ]; then echo ok; \
	else echo "FAIL (exit $$rc, expected 1)"; exit 1; fi

# provigil targets bash 3.2 (macOS system bash); see .shellcheckrc.
lint:
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "shellcheck not found — brew install shellcheck"; exit 1; }
	shellcheck $(SCRIPTS)

# `make test` is an alias for the two non-destructive checks.
test: check lint

install:
	./install.sh

uninstall:
	./uninstall.sh
