#!/bin/bash
# =============================================================================
# Script d'installation des prérequis (Windows/WSL)
# =============================================================================
# Usage: ./scripts/setup-wsl.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Setup WSL pour OpenClaw Ansible      ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# 1. Mise à jour système
echo -e "${YELLOW}[1/6] Mise à jour du système...${NC}"
sudo apt update && sudo apt upgrade -y

# 2. Installer Python et pip
echo -e "${YELLOW}[2/6] Installation de Python...${NC}"
sudo apt install -y python3 python3-pip python3-venv sshpass

# 3. Installer Ansible
echo -e "${YELLOW}[3/6] Installation d'Ansible...${NC}"
pip3 install --user ansible

# Ajouter au PATH si nécessaire
if ! command -v ansible &> /dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
fi

# 4. Installer les collections Ansible Galaxy
echo -e "${YELLOW}[4/6] Installation des collections Ansible...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
ansible-galaxy collection install -r requirements.yml

# 5. Générer une clé SSH si elle n'existe pas
echo -e "${YELLOW}[5/6] Vérification de la clé SSH...${NC}"
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Génération d'une nouvelle clé SSH..."
    ssh-keygen -t ed25519 -N "" -C "openclaw-deploy-key" -f ~/.ssh/id_ed25519
    echo ""
    echo -e "${GREEN}Clé SSH publique:${NC}"
    cat ~/.ssh/id_ed25519.pub
    echo ""
    echo "Copiez cette clé dans vault.yml (vault_ssh_public_key)"
else
    echo "Clé SSH existante trouvée."
    echo -e "${GREEN}Clé publique:${NC}"
    cat ~/.ssh/id_ed25519.pub
fi

# 6. Créer le vault si nécessaire
echo -e "${YELLOW}[6/6] Vérification du vault...${NC}"
if [ ! -f group_vars/vault.yml ]; then
    cp group_vars/vault.yml.example group_vars/vault.yml
    echo "vault.yml créé à partir du template."
    echo ""
    echo -e "${YELLOW}IMPORTANT: Éditez group_vars/vault.yml avec vos valeurs${NC}"
    echo "Utilisez: nano group_vars/vault.yml"
else
    echo "vault.yml existe déjà."
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   Installation terminée !              ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Prochaines étapes:"
echo "  1. Éditez group_vars/vault.yml avec vos valeurs"
echo "  2. Générez les secrets: bash scripts/generate-secrets.sh"
echo "  3. Chiffrez le vault: ansible-vault encrypt group_vars/vault.yml"
echo "  4. Copiez votre clé SSH sur le VPS: ssh-copy-id root@VOTRE_VPS_IP"
echo "  5. Lancez: bash deploy.sh"
echo ""
echo "Version Ansible installée:"
ansible --version | head -1
