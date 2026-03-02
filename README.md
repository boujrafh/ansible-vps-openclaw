# OpenClaw - Infrastructure Ansible Sécurisée

Infrastructure Ansible complète pour déployer OpenClaw de manière sécurisée sur un VPS Ubuntu avec Docker, Nginx et Cloudflare SSL.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      CLOUDFLARE                              │
│  (DNS + Proxy + WAF + DDoS Protection + SSL Full Strict)    │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTPS (443)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      VPS (Ubuntu 24.04)                      │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ UFW Firewall (2222, 80, 443) + Cloudflare IPs only     │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ Fail2ban (SSH + Nginx + Portscan protection)           │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ Auditd + Rkhunter + Kernel Hardening                   │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ Nginx (Reverse Proxy + SSL Cloudflare Origin)          │ │
│  │  └─ Rate limiting (50r/s) + Security Headers           │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ Docker                                                  │ │
│  │  └─ OpenClaw (conteneur sécurisé)                      │ │
│  │     ├─ no-new-privileges, cap_drop ALL                 │ │
│  │     ├─ read-only filesystem                            │ │
│  │     └─ resource limits (CPU + RAM)                     │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Fonctionnalités de sécurité

### Base
- **SSH Hardening** : Port 2222, clé uniquement, root désactivé, crypto moderne
- **UFW Firewall** : Deny par défaut, IPs Cloudflare whitelistées
- **Fail2ban** : Protection brute-force SSH, Nginx, portscan
- **SSL/TLS** : Certificats Origin Cloudflare (Full Strict)

### Avancée
- **Mises à jour automatiques** (unattended-upgrades)
- **Audit système** (auditd) : SSH, sudo, Docker, fichiers critiques
- **Détection de rootkits** (rkhunter)
- **Kernel hardening** (sysctl) : SYN flood, ASLR, anti-spoofing

### Docker
- Conteneur read-only avec tmpfs
- `no-new-privileges` + `cap_drop ALL`
- Limites CPU/RAM
- Rotation des logs
- Nettoyage automatique hebdomadaire

## Structure du projet

```
OpenClaw/
├── ansible.cfg              # Configuration Ansible
├── requirements.yml         # Dépendances Galaxy
├── deploy.sh                # Script déploiement (Linux/WSL)
├── deploy.bat               # Script déploiement (Windows)
├── .gitignore
├── inventory/
│   ├── production.yml       # Inventaire production
│   ├── staging.yml          # Inventaire staging
│   └── localhost.yml        # Exécution locale sur VPS
├── group_vars/
│   ├── all.yml              # Variables communes
│   ├── vault.yml            # Secrets (chiffré, gitignored)
│   └── vault.yml.example    # Template pour vault.yml
├── playbooks/
│   ├── site.yml             # Déploiement complet
│   ├── initial-setup.yml    # Config initiale (root)
│   ├── security.yml         # Sécurité de base
│   ├── security-advanced.yml # Sécurité avancée
│   ├── deploy-openclaw.yml  # Déployer OpenClaw
│   └── update-ssl.yml       # Mettre à jour SSL
├── roles/
│   ├── base/                # Config système + SSH
│   ├── security/            # UFW, Fail2ban, updates auto
│   ├── security_advanced/   # Auditd, rkhunter, sysctl
│   ├── docker/              # Docker CE + config
│   ├── nginx/               # Reverse proxy + templates
│   ├── cloudflare/          # Certificats SSL Origin
│   └── openclaw/            # Application OpenClaw
└── scripts/
    ├── setup-wsl.sh         # Installation prérequis WSL
    └── generate-secrets.sh  # Génération des secrets
```

## Installation (Windows 11 + WSL)

### 1. Prérequis

```bash
# Dans WSL (Ubuntu)
cd /mnt/c/devops/OpenClaw
bash scripts/setup-wsl.sh
```

Cela installe automatiquement:
- Python 3 + pip
- Ansible + collections Galaxy
- Génère une clé SSH
- Crée vault.yml à partir du template

### 2. Configurer les secrets

```bash
# Générer les mots de passe
bash scripts/generate-secrets.sh

# Éditer le vault avec les valeurs
nano group_vars/vault.yml
```

**Valeurs obligatoires :**

| Variable | Description |
|----------|-------------|
| `vault_vps_ip` | IP de votre VPS |
| `vault_ssh_public_key` | Votre clé SSH publique |
| `vault_cloudflare_origin_cert` | Certificat Origin Cloudflare |
| `vault_cloudflare_origin_key` | Clé privée Origin |
| `vault_deploy_password` | Mot de passe utilisateur deploy |
| `vault_openclaw_secret` | Secret interne OpenClaw |

### 3. Créer le certificat Cloudflare Origin

1. [Cloudflare Dashboard](https://dash.cloudflare.com) → votre domaine
2. SSL/TLS → Origin Server → Create Certificate
3. Hostnames: `*.votredomaine.com, votredomaine.com`
4. Copiez dans `vault.yml`

### 4. Chiffrer le vault

```bash
ansible-vault encrypt group_vars/vault.yml
```

### 5. Copier la clé SSH sur le VPS

```bash
ssh-copy-id root@VOTRE_VPS_IP
```

## Utilisation

### Méthode simple : Script interactif

```bash
bash deploy.sh
```

### Méthode manuelle

```bash
# Premier déploiement (connexion root, port 22)
ansible-playbook playbooks/initial-setup.yml -i inventory/production.yml \
  -u root --ask-pass --ask-vault-pass

# Déploiement complet (après initial-setup)
ansible-playbook playbooks/site.yml -i inventory/production.yml --ask-vault-pass

# OpenClaw uniquement
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml --ask-vault-pass

# Forcer le pull de l'image
ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml \
  -e force_pull=true --ask-vault-pass

# Dry-run (vérification sans modification)
ansible-playbook playbooks/site.yml -i inventory/production.yml \
  --check --diff --ask-vault-pass
```

### Playbooks disponibles

| Playbook | Description |
|----------|-------------|
| `site.yml` | Déploiement complet (tout) |
| `initial-setup.yml` | Configuration initiale (root, port 22) |
| `security.yml` | Sécurité de base (UFW, Fail2ban) |
| `security-advanced.yml` | Auditd, rkhunter, kernel hardening |
| `deploy-openclaw.yml` | Déployer/mettre à jour OpenClaw |
| `update-ssl.yml` | Renouveler les certificats SSL |

## Après déploiement

### Configurer Cloudflare DNS
- A record: `votredomaine.com` → VPS IP (Proxied)
- A record: `claw.votredomaine.com` → VPS IP (Proxied)
- SSL/TLS → Full (strict)

### Connexion SSH
```bash
ssh -p 2222 deploy@VOTRE_VPS_IP
```

### Vérifications
```bash
# Sur le VPS
sudo systemctl status ssh ufw fail2ban docker nginx auditd
sudo docker ps
sudo ufw status
sudo fail2ban-client status
```

## Maintenance

```bash
# Logs Fail2ban
sudo tail -f /var/log/fail2ban.log

# Logs Nginx
sudo tail -f /var/log/nginx/openclaw.access.log

# Logs Docker
sudo docker logs -f openclaw

# Scan rkhunter
sudo rkhunter --check

# Résumé des audits
sudo aureport --summary
```

## Sécurité du vault

```bash
# Chiffrer
ansible-vault encrypt group_vars/vault.yml

# Déchiffrer temporairement
ansible-vault decrypt group_vars/vault.yml

# Utiliser un fichier password
echo "votre-mot-de-passe" > .vault_pass
chmod 600 .vault_pass
ansible-playbook playbooks/site.yml --vault-password-file=.vault_pass
```

## Personnalisation

### Modifier le port SSH
Dans `group_vars/all.yml` :
```yaml
ssh_port: 2222  # Changez selon vos préférences
```

### Modifier les limites Docker
```yaml
openclaw_cpu_limit: "2.0"
openclaw_memory_limit: "1G"
```

### Désactiver une fonctionnalité
```yaml
ufw_enabled: false
fail2ban_enabled: false
auditd_enabled: false
rkhunter_enabled: false
```

## Licence

MIT
