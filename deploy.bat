@echo off
REM =============================================================================
REM Script de déploiement rapide OpenClaw (Windows)
REM Exécuter depuis WSL: wsl bash deploy.sh
REM Ou directement via Ansible si installé sous Windows
REM =============================================================================

echo ========================================
echo    OpenClaw Infrastructure Deployment
echo ========================================
echo.

REM Vérifier Ansible
where ansible-playbook >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Erreur: Ansible n'est pas installe
    echo Installez-le avec: pip install ansible
    echo Ou utilisez WSL: wsl bash deploy.sh
    exit /b 1
)

echo Choisissez une option:
echo 1) Configuration initiale (root)
echo 2) Deploiement complet
echo 3) Securite de base uniquement
echo 4) Securite avancee
echo 5) Deployer OpenClaw
echo 6) Verification (dry-run)
echo 7) Quitter
echo.
set /p choice="Votre choix [1-7]: "

if "%choice%"=="1" (
    echo Configuration initiale avec root...
    ansible-playbook playbooks/initial-setup.yml -i inventory/production.yml -u root --ask-pass --ask-vault-pass
)
if "%choice%"=="2" (
    echo Deploiement complet...
    ansible-playbook playbooks/site.yml -i inventory/production.yml --ask-vault-pass
)
if "%choice%"=="3" (
    echo Configuration securite...
    ansible-playbook playbooks/security.yml -i inventory/production.yml --ask-vault-pass
)
if "%choice%"=="4" (
    echo Configuration securite avancee...
    ansible-playbook playbooks/security-advanced.yml -i inventory/production.yml --ask-vault-pass
)
if "%choice%"=="5" (
    echo Deploiement OpenClaw...
    ansible-playbook playbooks/deploy-openclaw.yml -i inventory/production.yml --ask-vault-pass
)
if "%choice%"=="6" (
    echo Verification dry-run...
    ansible-playbook playbooks/site.yml -i inventory/production.yml --check --diff --ask-vault-pass
)
if "%choice%"=="7" (
    echo Au revoir!
    exit /b 0
)

echo.
echo Termine!
pause
