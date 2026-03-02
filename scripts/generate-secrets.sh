#!/bin/bash
# =============================================================================
# Script de génération des secrets pour vault.yml
# =============================================================================
# Usage: ./scripts/generate-secrets.sh
# =============================================================================

echo "=== Génération des secrets pour Ansible Vault ==="
echo ""
echo "Copiez ces valeurs dans votre group_vars/vault.yml"
echo ""
echo "# Mot de passe deploy:"
echo "vault_deploy_password: \"$(openssl rand -base64 32)\""
echo ""
echo "# OpenClaw secret:"
echo "vault_openclaw_secret: \"$(openssl rand -base64 32)\""
echo ""
echo "# PostgreSQL password:"
echo "vault_postgres_password: \"$(openssl rand -base64 24 | tr -d '/+=' | head -c 32)\""
echo ""
echo "# Ansible Vault password (à sauvegarder en lieu sûr):"
echo "Vault password suggestion: \"$(openssl rand -base64 24)\""
echo ""
echo "=== Fin de la génération ==="
echo ""
echo "N'oubliez pas de chiffrer le vault après édition:"
echo "  ansible-vault encrypt group_vars/vault.yml"
