#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 01.1 (Cloud Shell)
# Task: Push CSPR Scanner Image via Google Cloud Shell
# Author: Joabson Saccomani (jsaccomani@google.com)
# ==============================================================================
set -euo pipefail

# ANSI Color Codes
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${CYAN}${BOLD} [FASE 01.1 - CLOUD SHELL] Push da Imagem Scanner para Artifact Registry      ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

# 1. Auto-detect target project automatically without prompting if found
TARGET_PROJECT="${BQ_PROJECT_ID:-}"
if [[ -z "${TARGET_PROJECT}" ]]; then
    # Check active gcloud config project
    ACTIVE_GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
    if [[ -n "${ACTIVE_GCLOUD_PROJECT}" && "${ACTIVE_GCLOUD_PROJECT}" != "(unset)" ]]; then
        TARGET_PROJECT="${ACTIVE_GCLOUD_PROJECT}"
    fi
fi

if [[ -z "${TARGET_PROJECT}" ]]; then
    # Check summary file
    SUMMARY_FILE=$(ls -t "${BASE_DIR}"/cspr_environment_summary_*.txt "${BASE_DIR}"/local_tests/cspr_environment_summary_*.txt cspr_environment_summary_*.txt 2>/dev/null | head -n 1 || true)
    if [[ -n "${SUMMARY_FILE}" ]]; then
        TARGET_PROJECT=$(grep "GCP Project ID:" "${SUMMARY_FILE}" | awk '{print $NF}' || true)
    fi
fi

# Fallback only if completely missing
if [[ -z "${TARGET_PROJECT}" ]]; then
    read -r -p "Target GCP Project ID: " TARGET_PROJECT
fi

LOCATION="${LOCATION:-us-east1}"
PSO_SOURCE_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:v3.0.8"
FALLBACK_SOURCE_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:latest"

CUSTOMER_REPO="${LOCATION}-docker.pkg.dev/${TARGET_PROJECT}/customer-cspr-toolkit"
CUSTOMER_TARGET_IMAGE="${CUSTOMER_REPO}/cspr-prereq:latest"
CUSTOMER_ALT_TARGET="${CUSTOMER_REPO}/cspr-toolkit-prerequisites:latest"

# 2. Verify and enforce Google Account authentication for cloud-pso-security repo access
CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
echo -e "${BLUE}Verificação de Autenticação:${NC}"
echo -e " • Conta Ativa:        ${YELLOW}${CURRENT_ACCOUNT}${NC}"

if [[ "${CURRENT_ACCOUNT}" != *"@google.com" ]]; then
    echo -e "${YELLOW}[AVISO] O repositório oficial do Google PSO (cloud-pso-security) exige credenciais @google.com.${NC}"
    # Check if a @google.com account is already authenticated
    GOOGLE_ACCOUNT=$(gcloud auth list --format="value(account)" 2>/dev/null | grep "@google.com" | head -n 1 || true)
    
    if [[ -n "${GOOGLE_ACCOUNT}" ]]; then
        echo -e "${GREEN}[✔] Conta Google encontrada: ${GOOGLE_ACCOUNT}. Alternando automaticamente...${NC}"
        gcloud config set account "${GOOGLE_ACCOUNT}"
        CURRENT_ACCOUNT="${GOOGLE_ACCOUNT}"
    else
        echo -e "${CYAN}[AUTENTICAÇÃO NECESSÁRIA] Faça login com sua conta corporativa Google (@google.com):${NC}"
        gcloud auth login --brief
        CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null || true)
    fi
fi

echo ""
echo -e "${BLUE}Execution Parameters:${NC}"
echo -e " • Target Project:     ${GREEN}${TARGET_PROJECT}${NC} (Auto-detectado)"
echo -e " • Region:             ${GREEN}${LOCATION}${NC}"
echo -e " • Google Account:     ${GREEN}${CURRENT_ACCOUNT}${NC}"
echo -e " • Source PSO Image:   ${GREEN}${PSO_SOURCE_IMAGE}${NC}"
echo -e " • Destination Repo:   ${GREEN}${CUSTOMER_REPO}${NC}"
echo ""

# Verify Docker availability in Cloud Shell
if ! command -v docker &> /dev/null; then
    echo -e "${RED}[ERROR] Docker não encontrado. Certifique-se de executar este script dentro do Google Cloud Shell.${NC}"
    exit 1
fi

# 3. Configure Docker Authentication for Artifact Registry
echo -e "${CYAN}[1/5] Configurando autenticação do Docker no Artifact Registry...${NC}"
gcloud auth configure-docker "us-docker.pkg.dev,${LOCATION}-docker.pkg.dev" --quiet

# 4. Pull PSO Source Image
echo -e "${CYAN}[2/5] Baixando a imagem oficial do CSPR PSO (usando credenciais Google)...${NC}"
if ! docker pull "${PSO_SOURCE_IMAGE}"; then
    echo -e "${YELLOW}[AVISO] Tag v3.0.8 falhou, tentando tag 'latest'...${NC}"
    docker pull "${FALLBACK_SOURCE_IMAGE}"
    PSO_SOURCE_IMAGE="${FALLBACK_SOURCE_IMAGE}"
fi
echo -e "${GREEN}[✔] Imagem base baixada com sucesso.${NC}"

# 5. Tag Image for Customer Repository
echo -e "${CYAN}[3/5] Aplicando tags para o repositório do cliente...${NC}"
docker tag "${PSO_SOURCE_IMAGE}" "${CUSTOMER_TARGET_IMAGE}"
docker tag "${PSO_SOURCE_IMAGE}" "${CUSTOMER_ALT_TARGET}"
echo " - Tagged: ${CUSTOMER_TARGET_IMAGE}"
echo " - Tagged: ${CUSTOMER_ALT_TARGET}"

# 6. Push to Customer Artifact Registry
echo -e "${CYAN}[4/5] Enviando (Push) imagem para o Artifact Registry do cliente (${TARGET_PROJECT})...${NC}"
docker push "${CUSTOMER_TARGET_IMAGE}"
docker push "${CUSTOMER_ALT_TARGET}"

echo ""
echo -e "${CYAN}[5/5] Validando imagem no repositório...${NC}"
gcloud artifacts docker images list "${CUSTOMER_REPO}" --include-tags --project="${TARGET_PROJECT}"

echo ""
echo -e "${GREEN}${BOLD}==============================================================================${NC}"
echo -e "${GREEN}${BOLD} [✔] SUCESSO! A imagem do scanner foi publicada no repositório do projeto!     ${NC}"
echo -e "${GREEN}${BOLD}==============================================================================${NC}"
echo -e "Imagem pronta em: ${BOLD}${CUSTOMER_TARGET_IMAGE}${NC}"
echo ""
echo -e "${YELLOW}${BOLD}Próximo Passo:${NC}"
echo -e "Volte para o seu terminal no ${BOLD}Mac${NC} e execute a ${BOLD}Fase 03${NC}:"
echo -e "  ${CYAN}./pso_cspr_manager.sh${NC}  -> Opção ${BOLD}3${NC} (Deploy & Execução do Cloud Run Job)"
echo ""
