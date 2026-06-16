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
	@echo "→ source files SHOULD contain placeholders (sanity):"
	@found=$$(grep -rln '__CC_KIT_DIR__\|__CC_KIT_ROOT__' \
	    bin/ modules/ hooks/ init.sh 2>/dev/null | wc -l); \
	  if [ "$$found" -lt 5 ]; then \
	    echo "ERROR: expected __CC_KIT_DIR__ placeholders in source files, only found $$found"; exit 1; \
	  else \
	    echo "  ✓ $$found source files have placeholders (will be substituted at install)"; \
	  fi
	@echo "✓ all checks passed"

check-installed:
	@echo "→ checking installed copy at $(CC_KIT_ROOT) for unsubstituted placeholders..."
	@if [ ! -d "$(CC_KIT_ROOT)" ]; then \
	  echo "  ! $(CC_KIT_ROOT) does not exist; run 'make install-local' first"; exit 0; \
	fi
	@if grep -rln '__CC_KIT_DIR__\|__CC_KIT_ROOT__\|~/projects/cc-kit' \
	    $(CC_KIT_ROOT)/bin $(CC_KIT_ROOT)/modules $(CC_KIT_ROOT)/hooks $(CC_KIT_ROOT)/init.sh 2>/dev/null; then \
	  echo "ERROR: unsubstituted placeholders found in installed copy"; exit 1; \
	else \
	  echo "  ✓ installed copy has no remaining placeholders"; \
	fi

test:
	@echo "→ running bats tests..."
	@bats tests/ 2>&1 || (echo "bats not installed? try: brew install bats-core"; exit 1)

install-local:
	@echo "→ installing to $(CC_KIT_ROOT) (test path)..."
	CC_KIT_ROOT=$(CC_KIT_ROOT) $(SRC)/install.sh

clean:
	@echo "→ removing $(CC_KIT_ROOT)..."
	@rm -rf $(CC_KIT_ROOT)
