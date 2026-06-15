# Contributing to cc-kit

Thanks for your interest! cc-kit is intentionally small. Please read this
before opening a PR — most of the friction in this project is about
matching the existing style and not over-engineering.

## Code of conduct

Be kind. Assume good faith. We don't have a formal CoC document, but the
short version: be the kind of contributor you'd want to review your own PR.

---

## What we want

- **Bug fixes** that come with a failing test (or a clear repro)
- **New provider support** following the pattern in `docs/PROVIDERS.md`
- **Documentation improvements** — typos, clarity, missing edge cases
- **Performance** for the JSONL parser (currently ~0.02s per MB; good
  enough but can be better)

## What we don't want

- **New dependencies.** cc-kit has zero Python packages. Don't add one
  without a long, painful discussion.
- **Feature creep.** If your feature needs an extra config file, three
  hooks, and a daemon, it probably doesn't belong here.
- **Pure refactoring PRs** without a behavior change. The codebase is
  small enough that the next person can read the whole thing; if a
  refactor improves clarity, include before/after line counts in the PR.

---

## Development setup

```bash
git clone https://github.com/Huadous/cc-kit
cd cc-kit

# Install to a separate test path so you don't clobber your real config
make install-local
# or: CC_KIT_ROOT=~/.cc-kit-test ./install.sh

# Run static checks
make lint

# Run tests
make test
```

`make install-local` installs to `~/.cc-kit-test/` (does not touch
`~/.cc-kit/` or your real `~/.claude/settings.json`).

---

## Code style

### Bash

- `set -euo pipefail` at the top of every script
- Use `[[ ]]` for tests, never `[ ]`
- Quote everything: `"$var"`, not `$var`
- Functions in `modules/*.sh` use snake_case with a `monitor_` / `cc_` prefix
- Comments explain *why*, not *what*

```bash
# Good
local key="$(get_saved_key "$provider")"
if [[ -n "$key" ]]; then
    echo "Using saved ${provider} API key: $(mask_value "$key")" >&2
fi

# Bad
key=`get_saved_key $provider`
if [ ! -z "$key" ]; then
    echo "key=$key"
fi
```

### Python

- Python 3.8+ (we use f-strings)
- No external packages
- 4-space indent
- Keep functions small; if a function is over 50 lines, split it

---

## Testing

We use [bats-core](https://github.com/bats-core/bats-core). Tests live in
`tests/`. To add a test:

```bash
# tests/something.bats
@test "my function does X" {
    run bash -c 'source modules/monitor.sh && my_function "input"'
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}
```

For tests that need HTTP, mock the curl binary in `tests/mocks/curl`.

```bash
make test   # runs all tests
```

---

## Pull request process

1. **Open an issue first** for non-trivial changes. We don't want you to
   spend a day on something we'll reject for design reasons.
2. Fork, branch, code.
3. `make lint` passes.
4. `make test` passes (or new tests added for new behavior).
5. PR description explains:
   - What changed
   - Why
   - How you tested
   - Screenshots if UI changed (status line is UI)
6. Be patient. Reviewers are volunteers.

---

## Release process

- We follow semver. v0.x means "API may change"
- CHANGELOG.md gets an entry on every release
- Tags are `v0.1.0` (not `0.1.0`)
- Releases are cut from `main`

---

## Project structure

```
cc-kit/
├── bin/           # User-facing executables (the public API)
├── modules/       # Bash libraries (private)
├── hooks/         # Claude Code hook handlers
├── data/          # Runtime state (gitignored, with .example templates)
├── tests/         # Bats tests
├── docs/          # User-facing documentation
├── install.sh     # Entry: one-click install
├── uninstall.sh   # Entry: one-click uninstall
└── init.sh        # Bash entry: sourced by ~/.bashrc
```

If you add a new file, decide: is it for the user (`bin/`), for our own
code (`modules/`), for state (`data/`), or for Claude Code to call
(`hooks/`)?

---

## License

By contributing, you agree your contributions are licensed under
Apache 2.0 (the project's license). The CLA is implicit: PR = license
grant.
