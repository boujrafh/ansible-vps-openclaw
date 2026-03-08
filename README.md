# OpenClaw — Secure Ansible Infrastructure

Ansible infrastructure to deploy **OpenClaw** securely on an Ubuntu VPS using Docker, Nginx reverse proxy, and Cloudflare SSL. Runs entirely on the VPS itself using a local Ansible connection (no separate control machine required).

---

## Architecture

```
Internet
   │
   ▼
┌─────────────────────────────────────────────────┐
│  CLOUDFLARE  (DNS + Proxy + WAF + DDoS + SSL)   │
│  Mode: Full (Strict) — encrypts end-to-end      │
└──────────────────────┬──────────────────────────┘
                       │ HTTPS 443
                       ▼
┌─────────────────────────────────────────────────┐
│              VPS  Ubuntu 24.04                  │
│                                                 │
│  UFW Firewall                                   │
│    • SSH allowed on port 2222                   │
│    • HTTP/HTTPS only from Cloudflare IPs        │
│                                                 │
│  Fail2ban                                       │
│    • SSH brute-force protection                 │
│    • Nginx rate-limit and bot protection        │
│    • Port scan detection                        │
│                                                 │
│  Nginx (reverse proxy)                          │
│    • SSL with Cloudflare Origin certificate     │
│    • Rate limiting 50 req/s                     │
│    • Security headers (HSTS, X-Frame, etc.)     │
│    • Cloudflare real IP restoration             │
│         │                                       │
│         ▼ http://127.0.0.1:18791               │
│                                                 │
│  Docker — OpenClaw container                    │
│    • network_mode: host                         │
│    • read-only filesystem + tmpfs               │
│    • no-new-privileges, cap_drop ALL            │
│    • CPU and RAM limits                         │
│    • Daily data backup                          │
│                                                 │
│  Advanced security                              │
│    • auditd — system call auditing              │
│    • rkhunter — rootkit detection               │
│    • sysctl kernel hardening                    │
│    • Automatic security updates                 │
└─────────────────────────────────────────────────┘
```

---

## How Cloudflare Works Here

Cloudflare acts as a **reverse proxy** and security layer in front of your VPS.

### SSL/TLS — Full (Strict) Mode

There are two separate encrypted connections:

1. **Browser → Cloudflare**: standard HTTPS using Cloudflare's public certificate (trusted by all browsers)
2. **Cloudflare → Your VPS**: encrypted using a **Cloudflare Origin Certificate**

The **Origin Certificate** is issued by Cloudflare specifically for the link between Cloudflare's edge servers and your VPS. It is **not trusted by regular browsers** — only by Cloudflare. This is why SSL mode must be **Full (Strict)** and not **Full** or **Flexible**.

> If you set **Flexible**, Cloudflare connects to your VPS over plain HTTP — your data is not encrypted on the server side. Always use **Full (Strict)**.

### Why Cloudflare IPs Only on the Firewall

The UFW firewall only allows HTTP/HTTPS connections from Cloudflare's published IP ranges. This means:
- No one can connect directly to Nginx using your VPS IP
- All traffic must pass through Cloudflare's WAF and DDoS protection
- Your real server IP is hidden from the public internet

### Use an Unguessable Subdomain

Instead of `app.yourdomain.com` or `openclaw.yourdomain.com`, use a random subdomain like `portal-7x2k.yourdomain.com`. This prevents bots from discovering your service by scanning common subdomains.

### DNS Records Required

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| A | `@` | your VPS IP | ✅ Proxied (orange cloud) |
| A | `your-subdomain` | your VPS IP | ✅ Proxied (orange cloud) |

> **Never use DNS-only (grey cloud)** — that exposes your real VPS IP and bypasses the firewall and all Cloudflare protection.

---

## Prerequisites

- A VPS running **Ubuntu 24.04**
- A domain managed by **Cloudflare** (free account is sufficient)
- SSH access to the VPS as `root`
- A **Cloudflare Origin Certificate** (free, created in the dashboard)

---

## Installation

All commands are run **directly on the VPS** as root via SSH.

### 1. Connect to the VPS

```bash
ssh root@YOUR_VPS_IP
```

### 2. Install Ansible and Git

```bash
apt update && apt install -y git ansible-core
```

### 3. Clone the repository

```bash
git clone https://github.com/boujrafh/ansible-vps-openclaw.git /opt/openclaw-infra
cd /opt/openclaw-infra
ansible-galaxy collection install -r requirements.yml
```

### 4. Generate secrets

```bash
openssl rand -base64 32   # → vault_deploy_password
openssl rand -base64 32   # → vault_openclaw_secret
openssl rand -base64 32   # → vault_postgres_password
```

### 5. Generate the deploy SSH key

This key is installed into the `deploy` user's `authorized_keys`. After deployment you connect with this key instead of root.

```bash
ssh-keygen -t ed25519 -N "" -C "openclaw-deploy" -f ~/.ssh/openclaw_deploy
cat ~/.ssh/openclaw_deploy.pub   # copy this — goes into vault_ssh_public_key
```

### 6. Create the Cloudflare Origin Certificate

1. [Cloudflare Dashboard](https://dash.cloudflare.com) → your domain
2. **SSL/TLS → Origin Server → Create Certificate**
3. Leave defaults (RSA 2048, 15 years validity)
4. Hostnames: `yourdomain.com` and `*.yourdomain.com`
5. Click **Create** — copy both values **immediately** (the private key is shown only once)

### 7. Configure non-secret variables

```bash
nano /opt/openclaw-infra/group_vars/all.yml
```

Key values to change:

```yaml
domain: "yourdomain.com"
admin_email: "you@yourdomain.com"
timezone: "Europe/Brussels"         # your timezone
ssh_port: 2222                      # SSH moves to this port after deployment
openclaw_subdomain: "portal-7x2k"  # use something random and unguessable
openclaw_port: 18791
```

### 8. Configure secrets

```bash
cp group_vars/vault.yml.example group_vars/vault.yml
nano group_vars/vault.yml
```

Fill in every value:

```yaml
vault_vps_ip: "YOUR_VPS_IP"
vault_ssh_public_key: "ssh-ed25519 AAAA... openclaw-deploy"
vault_deploy_password: "generated-with-openssl"
vault_cloudflare_zone_id: "find-this-in-cloudflare-dashboard-right-sidebar"
vault_openclaw_secret: "generated-with-openssl"
vault_postgres_user: "openclaw"
vault_postgres_password: "generated-with-openssl"
vault_postgres_db: "openclaw"

vault_cloudflare_origin_cert: |
  -----BEGIN CERTIFICATE-----
  MIIEpjCCA46gA...  (every line indented with 2 spaces)
  -----END CERTIFICATE-----

vault_cloudflare_origin_key: |
  -----BEGIN PRIVATE KEY-----
  MIIEvQIBADANB...  (every line indented with 2 spaces)
  -----END PRIVATE KEY-----
```

> **Indentation is critical.** Every line inside certificate/key blocks must be indented with exactly 2 spaces. A missing space will break YAML parsing.

### 9. Update the inventory hostname

```bash
nano /opt/openclaw-infra/inventory/localhost.yml
```

Replace `localhost` with a meaningful server name:

```yaml
all:
  hosts:
    vps-openclaw:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
  vars:
    env: production
```

### 10. Encrypt the vault

```bash
ansible-vault encrypt group_vars/vault.yml
# Choose a strong password and save it — you will need it for every deployment
```

---

## Deployment

### Dry-run first (safe, no changes)

```bash
cd /opt/openclaw-infra
ansible-playbook playbooks/site.yml -i inventory/localhost.yml --check --diff --ask-vault-pass
```

### Full deployment

```bash
ansible-playbook playbooks/site.yml -i inventory/localhost.yml --ask-vault-pass
```

### Individual playbooks

```bash
# OpenClaw container only
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/localhost.yml --ask-vault-pass

# Force pull latest Docker image
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/localhost.yml \
  -e force_pull=true --ask-vault-pass

# Nginx only
ansible-playbook playbooks/site.yml -i inventory/localhost.yml \
  --tags nginx --ask-vault-pass

# Renew SSL certificate
ansible-playbook playbooks/update-ssl.yml -i inventory/localhost.yml --ask-vault-pass
```

### Available tags

| Tag | Runs |
|-----|------|
| `base` | System packages, SSH hardening, deploy user |
| `security` | UFW, Fail2ban, automatic updates |
| `docker` | Docker CE installation and daemon config |
| `cloudflare` | SSL certificate deployment |
| `nginx` | Nginx reverse proxy configuration |
| `openclaw` | OpenClaw container deployment |

---

## After Deployment

### Cloudflare DNS

Add these records in Cloudflare Dashboard → DNS:

| Type | Name | Value | Proxy Status |
|------|------|-------|-------------|
| A | `@` | your VPS IP | **Proxied** ✅ |
| A | `your-subdomain` | your VPS IP | **Proxied** ✅ |

Set **SSL/TLS mode → Full (strict)**.

### Verify services

```bash
systemctl status nginx docker fail2ban ufw ssh
docker ps
docker logs openclaw
ufw status verbose
fail2ban-client status
```

### Connect via SSH after deployment

SSH now requires the deploy key and uses port 2222. Root login is disabled.

```bash
ssh -p 2222 -i ~/.ssh/openclaw_deploy deploy@YOUR_VPS_IP
```

---

## Maintenance

### Logs

```bash
docker logs -f openclaw                            # OpenClaw
tail -f /var/log/nginx/openclaw.access.log         # Nginx access
tail -f /var/log/nginx/openclaw.error.log          # Nginx errors
tail -f /var/log/fail2ban.log                      # Banned IPs
aureport --summary                                 # Security audit summary
```

### Unban an IP

```bash
fail2ban-client unban THE_IP_ADDRESS
```

### Run rootkit scan

```bash
rkhunter --check
```

### Vault operations

```bash
ansible-vault decrypt group_vars/vault.yml   # decrypt to edit
nano group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml   # re-encrypt after editing

# Use a password file to avoid typing the password each time
echo "your-vault-password" > .vault_pass && chmod 600 .vault_pass
ansible-playbook playbooks/site.yml --vault-password-file=.vault_pass
# .vault_pass is gitignored — never commit it
```

---

## Project Structure

```
ansible-vps-openclaw/
├── ansible.cfg                    # Ansible config (local connection, smart caching)
├── requirements.yml               # Galaxy collections (community.docker, posix, general)
├── deploy.sh                      # Interactive deployment menu
├── group_vars/
│   ├── all.yml                    # All non-secret config — edit this
│   ├── vault.yml                  # Encrypted secrets (gitignored, create from example)
│   └── vault.yml.example          # Template showing all required vault variables
├── inventory/
│   ├── localhost.yml              # For running Ansible directly on the VPS
│   ├── production.yml             # For running Ansible from a remote control machine
│   └── staging.yml                # Staging environment
├── playbooks/
│   ├── site.yml                   # Full deployment — runs all roles in order
│   ├── initial-setup.yml          # First-time setup via root on port 22
│   ├── security.yml               # UFW + Fail2ban only
│   ├── security-advanced.yml      # auditd + rkhunter + sysctl only
│   ├── deploy-openclaw.yml        # OpenClaw container only
│   └── update-ssl.yml             # SSL certificate renewal
└── roles/
    ├── base/                      # Packages, SSH config, deploy user, system limits
    ├── security/                  # UFW, Fail2ban jails, unattended-upgrades
    ├── security_advanced/         # auditd rules, rkhunter, sysctl hardening
    ├── docker/                    # Docker CE, daemon.json, log rotation, cleanup cron
    ├── cloudflare/                # Deploys Origin cert/key to /etc/nginx/ssl/cloudflare/
    ├── nginx/                     # Reverse proxy, rate limiting, security headers
    └── openclaw/                  # Docker Compose, .env, backup cron
```

---

## Known Issues and Fixes Applied

These bugs were discovered during deployment and are already fixed in this repository.

| Error | Cause | Fix |
|-------|-------|-----|
| `Group docker does not exist` when creating deploy user | `base` role tried to add the user to `docker` group before Docker was installed | Added a `group: docker` creation task in `base/tasks/main.yml` before the user task |
| `nginx -t` fails — `rate-limiting.conf` not found | nginx.conf was validated before `conf.d/` files were created | Removed the premature `validate: "nginx -t -c %s"` from the nginx.conf template task |
| Duplicate `proxy_read_timeout` directive | Both `proxy-params.conf` snippet and `openclaw-site.conf` defined the same directive | Removed the duplicate lines from `openclaw-site.conf.j2` |
| OpenClaw crashes: `ENOENT mkdir '/home/node/.openclaw'` | Container has `read_only: true` but OpenClaw needs a writable home directory | Added `tmpfs` mount for `/home/node/.openclaw` in docker-compose template |
| 502 Bad Gateway — Nginx cannot reach OpenClaw | OpenClaw binds all ports to `127.0.0.1` inside the container; Docker port mapping cannot forward to loopback-only listeners | Changed to `network_mode: host` so the container shares the VPS network namespace directly |
| `version` key warning in Docker Compose | The `version:` attribute is obsolete in modern Docker Compose | Removed `version: '3.8'` from the compose template |

---

## Security Notes

- Root SSH login is **disabled** after deployment
- Password authentication over SSH is **disabled** — key only
- HTTP/HTTPS only accepted from **Cloudflare IP ranges** — direct VPS access is blocked
- `group_vars/vault.yml` and `.vault_pass` are **gitignored** — never commit them
- OpenClaw container runs with `no-new-privileges`, `cap_drop: ALL`, read-only filesystem
- Automatic security updates are configured via `unattended-upgrades`
- Fail2ban bans IPs after repeated failed SSH or Nginx requests

---

## License

MIT
