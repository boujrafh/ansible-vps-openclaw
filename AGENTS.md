# AGENTS.md — OpenClaw Infrastructure

Guide pour les agents IA travaillant sur ce projet Ansible. Ce projet déploie l'application **OpenClaw** de manière sécurisée sur un VPS Ubuntu.

---

## Vue d'ensemble du projet

Ce projet utilise **Ansible** pour provisionner et configurer un VPS Ubuntu 24.04 avec :

- **OpenClaw** — Application conteneurisée (Docker)
- **Nginx** — Reverse proxy avec rate limiting et headers de sécurité
- **Cloudflare** — SSL/TLS en mode Full (Strict) + protection DDoS/WAF
- **Sécurité multicouche** — UFW, Fail2ban, auditd, rkhunter, kernel hardening

### Flux de trafic

```
Internet → Cloudflare (SSL/WAF/DDoS) → UFW (IPs Cloudflare uniquement) 
  → Nginx (rate limit + headers) → Docker/OpenClaw (localhost:18791)
```

---

## Structure du projet

```
ansible-vps-openclaw/
├── ansible.cfg              # Configuration Ansible (inventory par défaut, SSH, etc.)
├── requirements.yml         # Collections Ansible Galaxy requises
├── deploy.sh                # Script interactif de déploiement (menu)
├── deploy.bat               # Wrapper Windows (délègue à WSL)
├── group_vars/
│   ├── all.yml              # Variables non-sensibles (configurable)
│   ├── vault.yml            # Secrets chiffrés (ansible-vault, gitignored)
│   └── vault.yml.example    # Template pour vault.yml
├── inventory/
│   ├── localhost.yml        # Exécution sur le VPS lui-même (ansible_connection: local)
│   ├── production.yml       # Déploiement depuis machine distante
│   └── staging.yml          # Environnement de test
├── playbooks/
│   ├── site.yml             # Déploiement complet (tous les rôles)
│   ├── initial-setup.yml    # Première configuration (root, port 22)
│   ├── security.yml         # UFW + Fail2ban uniquement
│   ├── security-advanced.yml # auditd + rkhunter + sysctl
│   ├── deploy-openclaw.yml  # Mise à jour OpenClaw uniquement
│   └── update-ssl.yml       # Renouvellement certificats SSL
├── roles/
│   ├── base/                # Paquets, SSH durci, utilisateur deploy
│   ├── security/            # UFW (IPs Cloudflare), Fail2ban, unattended-upgrades
│   ├── security_advanced/   # auditd, rkhunter, kernel hardening (sysctl)
│   ├── docker/              # Docker CE, daemon.json, log rotation, cleanup cron
│   ├── cloudflare/          # Déploiement certificats Origin SSL
│   ├── nginx/               # Reverse proxy, rate limiting, sécurité
│   └── openclaw/            # docker-compose, .env, backup cron
└── scripts/
    ├── setup-wsl.sh         # Installation prérequis sous WSL
    └── generate-secrets.sh  # Génération de secrets aléatoires
```

---

## Prérequis et installation

### Environnement d'exécution

Ce projet est conçu pour fonctionner depuis :
- **WSL (Ubuntu)** sur Windows — exécution recommandée
- **Directement sur le VPS** — via `inventory/localhost.yml`
- **Machine de contrôle Linux/Mac** — via `inventory/production.yml`

> **Important** : Ne jamais exécuter depuis PowerShell/CMD Windows directement. Utiliser WSL.

### Installation initiale (WSL)

```bash
# Une seule fois — installe Ansible, collections, clé SSH, vault template
bash scripts/setup-wsl.sh

# Installation manuelle des collections uniquement
ansible-galaxy collection install -r requirements.yml
```

### Dépendances

| Outil | Version | Usage |
|-------|---------|-------|
| Ansible | ≥2.12 | Orchestration |
| community.docker | ≥3.0.0 | Gestion Docker/Compose |
| community.general | ≥6.0.0 | Modules génériques |
| ansible.posix | ≥1.5.0 | Modules POSIX (firewall, selinux) |

---

## Commandes principales

### Script interactif (recommandé)

```bash
bash deploy.sh
```

Options du menu :
1. Configuration initiale (root, port 22)
2. Déploiement complet
3. Sécurité de base
4. Sécurité avancée
5. Déployer/Mettre à jour OpenClaw
6. Mettre à jour certificats SSL
7. Vérification (dry-run)

### Commandes manuelles

```bash
# Configuration initiale (premier déploiement uniquement)
ansible-playbook playbooks/initial-setup.yml -i inventory/production.yml \
  -u root --ask-pass --ask-vault-pass

# Déploiement complet (après initial-setup)
ansible-playbook playbooks/site.yml -i inventory/production.yml --ask-vault-pass

# Déployer uniquement OpenClaw
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml --ask-vault-pass

# Forcer le pull de l'image Docker
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml \
  -e force_pull=true --ask-vault-pass

# Dry-run (vérification sans modification)
ansible-playbook playbooks/site.yml -i inventory/production.yml --check --diff --ask-vault-pass

# Exécuter un rôle spécifique avec tag
ansible-playbook playbooks/site.yml -i inventory/production.yml --tags nginx --ask-vault-pass
```

### Tags disponibles

| Tag | Rôle associé | Description |
|-----|--------------|-------------|
| `base` | base | Paquets système, SSH, utilisateur |
| `security` | security | UFW, Fail2ban |
| `docker` | docker | Docker CE et configuration |
| `cloudflare` | cloudflare | Certificats SSL |
| `nginx` | nginx | Reverse proxy |
| `openclaw` | openclaw | Application container |

---

## Configuration

### Variables non-sensibles (`group_vars/all.yml`)

Fichier modifiable directement — contient la configuration générale :

```yaml
domain: "example.com"
admin_email: "admin@example.com"
timezone: "Europe/Brussels"
ssh_port: 2222                    # SSH déplacé sur ce port
openclaw_subdomain: "portal-7x2k" # Nom aléatoire recommandé
openclaw_port: 18791              # Port interne OpenClaw

# Feature flags (désactivables)
ufw_enabled: true
fail2ban_enabled: true
auditd_enabled: true
rkhunter_enabled: true
sysctl_hardening: true
unattended_upgrades_enabled: true
```

### Secrets (`group_vars/vault.yml`)

**NE JAMAIS COMMITTER CE FICHIER NON-CHIFFRÉ.**

```bash
# Création à partir du template
cp group_vars/vault.yml.example group_vars/vault.yml

# Édition
nano group_vars/vault.yml

# Chiffrement obligatoire avant commit
ansible-vault encrypt group_vars/vault.yml

# Édition ultérieure
ansible-vault decrypt group_vars/vault.yml
nano group_vars/vault.yml
ansible-vault encrypt group_vars/vault.yml
```

Variables requises dans `vault.yml` :
- `vault_vps_ip` — Adresse IP du VPS
- `vault_ssh_public_key` — Clé publique SSH pour l'utilisateur deploy
- `vault_deploy_password` — Mot de passe chiffré de l'utilisateur deploy
- `vault_cloudflare_origin_cert` — Certificat Origin Cloudflare
- `vault_cloudflare_origin_key` — Clé privée Origin Cloudflare
- `vault_cloudflare_zone_id` — Zone ID Cloudflare
- `vault_openclaw_secret` — Secret interne OpenClaw
- `vault_postgres_user/password/db` — Credentials base de données

### Inventaires

| Fichier | Usage | Connexion |
|---------|-------|-----------|
| `localhost.yml` | Exécution sur le VPS | `ansible_connection: local` |
| `production.yml` | Déploiement distant | SSH vers `vault_vps_ip:2222` |
| `staging.yml` | Tests | SSH vers environnement staging |

---

## Architecture des rôles

### Ordre d'exécution (`site.yml`)

1. **base** — Fondation système
   - Mise à jour paquets
   - Création utilisateur `deploy` (groupe docker, sudo)
   - Configuration SSH durcie (port 2222, clé uniquement, root désactivé)
   - Limites système (limits.conf)

2. **security** — Sécurité réseau
   - UFW : deny all incoming, allow SSH + HTTP/HTTPS depuis IPs Cloudflare uniquement
   - Fail2ban : jails sshd, nginx-http-auth, nginx-botsearch, nginx-limit-req
   - Unattended-upgrades : mises à jour sécurité automatiques

3. **docker** — Conteneurisation
   - Installation Docker CE (depuis repo officiel)
   - Configuration daemon.json (log rotation, réseau)
   - Création réseau `web`
   - Cron de nettoyage hebdomadaire

4. **cloudflare** — SSL
   - Déploiement certificat Origin et clé privée
   - Script de vérification d'expiration

5. **nginx** — Reverse proxy
   - Configuration principale avec worker processes auto
   - Rate limiting (50 req/s, burst 20)
   - Headers de sécurité (HSTS, X-Frame, etc.)
   - Restoration Real-IP Cloudflare
   - Site OpenClaw avec upstream vers localhost:18791

6. **openclaw** — Application
   - Génération docker-compose.yml et .env
   - Pull image `ghcr.io/openclaw/openclaw:latest`
   - Démarrage conteneur avec healthcheck
   - Backup quotidien des données

### Sécurité du conteneur OpenClaw

```yaml
# docker-compose.yml généré
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
read_only: true
tmpfs:
  - /tmp:noexec,nosuid,size=100m
network_mode: host  # Nécessaire car OpenClaw bind sur 127.0.0.1
```

---

## Conventions de code

### Style Ansible

- **YAML** : Indentation de 2 espaces
- **Comments** : En français, format `# ===== Section =====`
- **Noms de variables** : Snakes case, préfixe `vault_` pour les secrets
- **Tags** : Toujours présents sur chaque task, regroupés par fonctionnalité
- **Handlers** : Utilisés pour restart/reload des services

### Templates Jinja2

- Extension `.j2`
- Header indiquant fichier généré par Ansible
- Variables validées avec `| default()` quand pertinent

### Structure de rôle

```
roles/nom/
├── tasks/
│   └── main.yml       # Tâches principales
├── handlers/
│   └── main.yml       # Handlers (restart, reload)
├── templates/
│   └── *.j2           # Templates de configuration
└── defaults/          # (optionnel) Variables par défaut
```

---

## Tests et vérification

### Avant déploiement

```bash
# Vérification syntaxique
ansible-playbook playbooks/site.yml --syntax-check

# Dry-run complet
ansible-playbook playbooks/site.yml -i inventory/production.yml \
  --check --diff --ask-vault-pass
```

### Après déploiement

```bash
# Vérification services
systemctl status nginx docker fail2ban ufw ssh
docker ps
docker logs openclaw

# Vérification pare-feu
ufw status verbose

# Vérification Fail2ban
fail2ban-client status

# Vérification auditd
aureport --summary
```

---

## Sécurité

### Points critiques

1. **Vault** — `group_vars/vault.yml` et `.vault_pass` sont gitignored
   - Toujours chiffrer avec `ansible-vault encrypt` avant commit
   - Ne jamais committer de secrets en clair

2. **SSH** — Après initial-setup :
   - Port déplacé à 2222 (configurable)
   - Authentification par clé uniquement
   - Root login désactivé

3. **Firewall** — UFW configuré pour :
   - N'accepter HTTP/HTTPS que depuis IPs Cloudflare
   - Bloquer tout accès direct au VPS

4. **Conteneur** — Hardening Docker :
   - Filesystem read-only
   - Capabilities dropped
   - No new privileges
   - Limits CPU/RAM

### Débanissement IP

```bash
fail2ban-client unban ADRESSE_IP
```

---

## Dépannage courant

| Problème | Cause | Solution |
|----------|-------|----------|
| `Group docker does not exist` | Ordre d'exécution | Correction appliquée : création groupe avant user |
| `nginx -t` échoue | Validation prématurée | Correction : pas de validation avant création conf.d/ |
| 502 Bad Gateway | Port binding | Correction : `network_mode: host` requis |
| OpenClaw crash `ENOENT` | Filesystem read-only | Correction : tmpfs pour `/home/node/.openclaw` |
| Warning Docker Compose | Clé `version:` obsolète | Correction : clé retirée du template |

---

## Ressources externes

- [Documentation Ansible](https://docs.ansible.com/)
- [Cloudflare Origin Certificates](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)
- [Docker Security](https://docs.docker.com/engine/security/)
- [Fail2ban Documentation](https://www.fail2ban.org/wiki/index.php/Main_Page)

---

## Licence

MIT
