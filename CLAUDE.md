# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is an Ansible infrastructure project for deploying OpenClaw securely on a Ubuntu VPS using Docker, Nginx, and Cloudflare SSL. All commands must be run from within WSL (Ubuntu) on Windows, not from the Windows shell directly.

## Environment Setup (WSL)

```bash
# First-time setup — installs Ansible, collections, SSH key, vault template
bash scripts/setup-wsl.sh

# Install Galaxy collections only
ansible-galaxy collection install -r requirements.yml
```

## Key Commands

### Interactive deploy script
```bash
bash deploy.sh
```

### Manual playbook execution
```bash
# Initial setup — runs as root on port 22 (first-time only)
ansible-playbook playbooks/initial-setup.yml -i inventory/production.yml \
  -u root --ask-pass --ask-vault-pass

# Full deployment (after initial-setup)
ansible-playbook playbooks/site.yml -i inventory/production.yml --ask-vault-pass

# Deploy/update OpenClaw only
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml --ask-vault-pass

# Force Docker image pull
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml \
  -e force_pull=true --ask-vault-pass

# Dry-run (check + diff without changes)
ansible-playbook playbooks/site.yml -i inventory/production.yml --check --diff --ask-vault-pass

# Run specific role with tag
ansible-playbook playbooks/site.yml -i inventory/production.yml --tags nginx --ask-vault-pass
```

### Vault management
```bash
# Create vault from template
cp group_vars/vault.yml.example group_vars/vault.yml

# Generate secrets
bash scripts/generate-secrets.sh

# Encrypt vault
ansible-vault encrypt group_vars/vault.yml

# Use a password file instead of prompting
ansible-playbook playbooks/site.yml --vault-password-file=.vault_pass
```

## Architecture

### Playbook execution order
`site.yml` runs all roles in sequence: `base → security → docker → cloudflare → nginx → openclaw`

Each playbook maps to specific roles:
- `initial-setup.yml` — bootstraps the VPS from root, creates `deploy` user
- `security.yml` — UFW + Fail2ban
- `security-advanced.yml` — auditd, rkhunter, sysctl kernel hardening
- `deploy-openclaw.yml` — Docker container lifecycle only
- `update-ssl.yml` — Cloudflare Origin cert renewal

### Variables
- `group_vars/all.yml` — all non-secret config (ports, limits, IPs, feature flags)
- `group_vars/vault.yml` — secrets (gitignored, must be created from `vault.yml.example`)
- `inventory/production.yml` — references `vault_vps_ip` for host; uses `deploy` user on port 2222

### Inventory
The default inventory in `ansible.cfg` points to `inventory/production.yml`. Staging uses `inventory/staging.yml`. For running playbooks directly on the VPS, use `inventory/localhost.yml`.

### Roles
| Role | Responsibility |
|------|----------------|
| `base` | System packages, SSH hardening (port 2222, key-only), resource limits |
| `security` | UFW (Cloudflare IPs whitelisted), Fail2ban (SSH + Nginx jails), unattended-upgrades |
| `security_advanced` | auditd rules, rkhunter, sysctl kernel hardening |
| `docker` | Docker CE, daemon config, log rotation, weekly cleanup cron |
| `cloudflare` | Deploys Cloudflare Origin SSL cert/key to `/etc/nginx/ssl/cloudflare/` |
| `nginx` | Reverse proxy config, rate limiting (50r/s), security headers, Cloudflare real-IP |
| `openclaw` | docker-compose deployment with hardened container (read-only fs, no-new-privileges, cap_drop ALL) |

### Security model
Traffic flow: `Cloudflare (SSL Full Strict) → UFW (Cloudflare IPs only on 80/443) → Nginx (rate limit + headers) → Docker (OpenClaw on port 8080)`

SSH is on port 2222, key-only, root login disabled. After `initial-setup.yml`, all subsequent playbooks connect as `deploy` user with sudo.

## Important Conventions

- **Secrets** — Never commit `group_vars/vault.yml` or `.vault_pass` (gitignored). Always encrypt with `ansible-vault` before pushing.
- **SSH key** — Production inventory expects `~/.ssh/id_ed25519`.
- **Feature flags** — Individual security components can be disabled in `all.yml` via `ufw_enabled`, `fail2ban_enabled`, `auditd_enabled`, `rkhunter_enabled`.
- **Tags** — Every role has a matching tag (`base`, `security`, `docker`, `cloudflare`, `nginx`, `openclaw`) for targeted runs.
- **Diff mode** — `ansible.cfg` enables `always = True` for diffs by default.
