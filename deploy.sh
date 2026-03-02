#!/bin/bash
# =============================================================================
# Script de déploiement rapide - OpenClaw
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   OpenClaw Infrastructure Deployment   ${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Vérifier Ansible
if ! command -v ansible-playbook &> /dev/null; then
    echo -e "${RED}Erreur: Ansible n'est pas installé${NC}"
    echo "Installez-le avec: pip install ansible"
    exit 1
fi

# Vérifier le vault
if [ ! -f "group_vars/vault.yml" ]; then
    echo -e "${RED}Erreur: group_vars/vault.yml n'existe pas${NC}"
    echo "Copiez le template: cp group_vars/vault.yml.example group_vars/vault.yml"
    exit 1
fi

# Menu
echo "Choisissez une option:"
echo -e "  ${CYAN}1)${NC} Configuration initiale (root, port 22)"
echo -e "  ${CYAN}2)${NC} Déploiement complet"
echo -e "  ${CYAN}3)${NC} Sécurité de base uniquement"
echo -e "  ${CYAN}4)${NC} Sécurité avancée (auditd, rkhunter, kernel)"
echo -e "  ${CYAN}5)${NC} Déployer/Mettre à jour OpenClaw"
echo -e "  ${CYAN}6)${NC} Mettre à jour les certificats SSL"
echo -e "  ${CYAN}7)${NC} Vérification (dry-run)"
echo -e "  ${CYAN}8)${NC} Quitter"
echo ""
read -p "Votre choix [1-8]: " choice

case $choice in
    1)
        echo -e "${YELLOW}Configuration initiale avec root...${NC}"
        ansible-playbook playbooks/initial-setup.yml -i inventory/production.yml \
            -u root --ask-pass --ask-vault-pass
        ;;
    2)
        echo -e "${YELLOW}Déploiement complet...${NC}"
        ansible-playbook playbooks/site.yml -i inventory/production.yml \
            --ask-vault-pass
        ;;
    3)
        echo -e "${YELLOW}Configuration sécurité de base...${NC}"
        ansible-playbook playbooks/security.yml -i inventory/production.yml \
            --ask-vault-pass
        ;;
    4)
        echo -e "${YELLOW}Configuration sécurité avancée...${NC}"
        ansible-playbook playbooks/security-advanced.yml -i inventory/production.yml \
            --ask-vault-pass
        ;;
    5)
        echo -e "${YELLOW}Déploiement OpenClaw...${NC}"
        read -p "Forcer le pull de l'image ? [y/N]: " force_pull
        EXTRA=""
        if [ "$force_pull" = "y" ] || [ "$force_pull" = "Y" ]; then
            EXTRA="-e force_pull=true"
        fi
        ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml \
            --ask-vault-pass $EXTRA
        ;;
    6)
        echo -e "${YELLOW}Mise à jour des certificats SSL...${NC}"
        ansible-playbook playbooks/update-ssl.yml -i inventory/production.yml \
            --ask-vault-pass
        ;;
    7)
        echo -e "${YELLOW}Vérification (dry-run)...${NC}"
        ansible-playbook playbooks/site.yml -i inventory/production.yml \
            --check --diff --ask-vault-pass
        ;;
    8)
        echo -e "${GREEN}Au revoir!${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}Choix invalide${NC}"
        exit 1
        ;;
esac

echo ""
echo -e "${GREEN}Terminé!${NC}"
