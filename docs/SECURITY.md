# Security policy

cc-kit is a local-only tool. It runs entirely on your machine, makes API
calls to providers you choose, and stores secrets in a file with
`chmod 600` permissions.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Email: `<maintainer-email>` (TBD — add before v0.1.0 release)
or open a private security advisory on GitHub:
`https://github.com/Huadous/cc-kit/security/advisories/new`

We will respond within 72 hours. We follow coordinated disclosure.

## What counts as a security issue

- **Secret leakage**: anything that causes an API key to be logged, written
  to a world-readable file, or transmitted to a destination other than the
  configured provider
- **Code execution**: shell injection, path traversal, or any way a crafted
  file or URL makes cc-kit run unintended commands
- **Privilege escalation**: cc-kit runs as the user; we don't expect root,
  but if you find a way to make it do something outside the user's
  permissions, that's a bug

## What does **not** count (and is fine as a public issue)

- Status line layout / cosmetic issues
- Provider API quirks (we can't fix MiniMax's response shape)
- Feature requests

## Threat model

| Asset | Adversary | Mitigation |
|---|---|---|
| Your API key | Accidental `git commit` | `.gitignore` at top level + nested in `data/`, optional `gitleaks` pre-commit hook |
| Your API key | Other local users | `chmod 600` on `secrets.env` |
| Your API key | `ps` output | API key only set as shell var in `provider.env`, not in CLI args |
| Usage history | Other local users | `usage.db` not particularly sensitive, but you can `rm` it anytime |
| Your prompts | Us (cc-kit maintainers) | **N/A** — we never see your prompts. cc-kit is local. |
| Install pipeline (curl pipe to bash) | MITM | `curl -fsSL` + (planned for v0.2) GPG-signed releases |

## Dependencies

cc-kit has:
- **Zero** Python third-party packages
- **Zero** npm / cargo / go modules
- **System packages**: `bash`, `python3`, `curl`, `bc`, `awk`, `grep`

This is intentional. A smaller supply chain is a safer one.

---

Last updated: 2026-06-16
