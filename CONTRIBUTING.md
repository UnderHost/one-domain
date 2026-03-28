# Contributing to UnderHost One-Domain

Thank you for your interest in contributing. This document explains the process and expectations.

---

## Before You Start

- Open an issue first for non-trivial changes — especially anything touching OS detection, package installation, SSL, or security hardening.
- Discuss breaking changes before submitting a PR.
- Small fixes (typos, minor safety improvements) can be submitted directly as a pull request.

---

## Project Scope

One-Domain is intentionally narrow in scope. It provisions a single-domain web server stack and nothing more. Contributions that expand scope (multi-domain management, control panel features, GUI tooling) will likely be declined.

**In scope:**
- Bug fixes and correctness improvements
- Support for new OS versions in the supported matrix (Ubuntu 25+, Debian 13, AlmaLinux 10)
- Security hardening improvements
- PHP version support updates
- Performance tuning improvements
- Documentation and example config improvements

**Out of scope:**
- Multi-domain management
- cPanel/Plesk/GUI features
- Adding support for unsupported/EOL distros (CentOS, Ubuntu 20/22, Debian 11)
- Non-standard or exotic software stacks

---

## Development Setup

You need:

- Bash 5.0+
- `shellcheck` installed locally
- A test VM or VPS running one of the supported OS targets
- Git

```bash
git clone https://github.com/UnderHost/one-domain.git
cd one-domain
```

---

## Code Standards

### Shell scripting

- All scripts use `#!/usr/bin/env bash` and `set -euo pipefail`
- `IFS=$'\n\t'` is set in the entrypoint — be careful with word splitting in module functions
- Quote all variable expansions: `"$var"`, not `$var`
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `local` for all function-local variables
- Functions are named with `snake_case`
- Module-private functions are prefixed with `_` (e.g. `_nginx_global_hardening`)
- Guard against double-sourcing with `[[ -n "${_UH_MODULE_LOADED:-}" ]] && return 0`
- Run `shellcheck` before submitting:

```bash
shellcheck --rcfile=.shellcheckrc install lib/*.sh modules/*.sh
```

### Module structure

Each module file in `modules/` must:

1. Start with the double-source guard
2. Export only functions that are called from `install` or other modules
3. Prefix private helpers with `_`
4. Use the logging helpers from `lib/core.sh`: `step`, `ok`, `info`, `warn`, `die`
5. Not hardcode paths — use `os_*` resolver functions from `modules/os.sh`

### Adding a new module

1. Create `modules/yourmodule.sh`
2. Add it to `_REQUIRED_MODULES` or `_OPTIONAL_MODULES` in `install`
3. Add a corresponding check to `.github/workflows/shellcheck.yml` under `REQUIRED`
4. Document the module's exported functions in its header comment

---

## Testing

Test on the full supported matrix before submitting:

| OS | Versions |
|----|---------|
| Ubuntu | 24.04 |
| Debian | 12 |
| AlmaLinux | 9 |

Minimum test checklist:

- [ ] `./install --help` runs without error
- [ ] `./install --dry-run example.com php` prints a clean plan
- [ ] `./install --dry-run example.com wp` prints a clean plan
- [ ] ShellCheck passes: `shellcheck --rcfile=.shellcheckrc install lib/*.sh modules/*.sh`
- [ ] Full install of `php` mode on a clean Ubuntu 24.04 VM
- [ ] Full install of `wp` mode on a clean AlmaLinux 9 VM
- [ ] `./install status example.com` works after install
- [ ] `./install diagnose example.com` works after install

---

## Pull Request Process

1. Fork the repository and create a branch: `git checkout -b fix/short-description`
2. Make your changes following the code standards above
3. Run ShellCheck locally and fix all issues
4. Test on at least one supported OS
5. Update `docs/CHANGELOG.md` with a brief entry under the `[Unreleased]` heading
6. Submit the PR with a clear description of what changed and why
7. Reference any related issue: `Closes #123`

---

## Commit Messages

Use conventional commit format:

```
type(scope): short description

Longer explanation if needed.
```

**Types:** `fix`, `feat`, `security`, `docs`, `refactor`, `test`, `chore`

**Examples:**

```
fix(os): correct PHP-FPM service name on Debian/Ubuntu
security(hardening): add kernel kptr_restrict parameter
feat(ssl): add OCSP stapling to post-certbot hardening
docs(readme): fix license badge mismatch (GPLv2 → GPL-3.0)
```

---

## Reporting Issues

Use GitHub Issues. Include:

- OS name and version (`cat /etc/os-release`)
- Installer version (`./install version`)
- The exact command you ran
- Relevant output from `/var/log/underhost_install.log`

For security vulnerabilities, see [SECURITY.md](SECURITY.md) — do **not** open a public issue.

---

## License

By contributing, you agree that your contributions will be licensed under the same [GPL-3.0 license](LICENSE) as the project.
