.PHONY: test lint install-local clean help

CC_KIT_ROOT ?= $(HOME)/.cc-kit-test
SRC := $(CURDIR)

help:
	@echo "cc-kit make targets:"
	@echo "  make test           Run bats unit tests"
	@echo "  make lint           Run shellcheck + pyflakes + placeholder check"
	@echo "  make install-local  Install to $(CC_KIT_ROOT) (test path)"
	@echo "  make clean          Remove test install at $(CC_KIT_ROOT)"

lint:
	@echo "→ shellcheck..."
	@shellcheck -S warning \
	  bin/cc-balance bin/cc-help bin/cc-mode bin/cc-status bin/cc-switch \
	  hooks/* modules/* \
	  install.sh init.sh uninstall.sh 2>&1 \
	  || (echo "shellcheck failed"; exit 1)
	@echo "→ pyflakes..."
	@python3 -m pyflakes bin/*.py 2>&1 \
	  || (echo "pyflakes failed"; exit 1)
	@echo "→ bash syntax..."
	@bash -n install.sh init.sh uninstall.sh
	@for f in bin/* hooks/* modules/*; do bash -n "$$f" 2>/dev/null || true; done
	@echo "→ placeholder check..."
	@if grep -rln '__CC_KIT_DIR__\|__CC_KIT_ROOT__\|~/projects/cc-kit' \
	    bin/ modules/ hooks/ init.sh 2>/dev/null; then \
	  echo "ERROR: unsubstituted placeholders found"; exit 1; \
	fi
	@echo "✓ all checks passed"

test:
	@echo "→ running bats tests..."
	@bats tests/ 2>&1 || (echo "bats not installed? try: brew install bats-core"; exit 1)

install-local:
	@echo "→ installing to $(CC_KIT_ROOT) (test path)..."
	CC_KIT_ROOT=$(CC_KIT_ROOT) $(SRC)/install.sh

clean:
	@echo "→ removing $(CC_KIT_ROOT)..."
	@rm -rf $(CC_KIT_ROOT)
