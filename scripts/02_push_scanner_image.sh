#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 02
# Task: Push CSPR Scanner Image to Customer Artifact Registry
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
echo -e "${CYAN}${BOLD} [FASE 02] Push CSPR Scanner Image to Customer Artifact Registry              ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

# Auto-detect target project automatically without prompting
if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
    ACTIVE_GCLOUD_PROJECT=$(gcloud config get-value project 2>/dev/null || true)
    if [[ -n "${ACTIVE_GCLOUD_PROJECT}" && "${ACTIVE_GCLOUD_PROJECT}" != "(unset)" ]]; then
        BQ_PROJECT_ID="${ACTIVE_GCLOUD_PROJECT}"
    else
        SUMMARY_FILE=$(ls -t "${BASE_DIR}"/cspr_environment_summary_*.txt "${BASE_DIR}"/local_tests/cspr_environment_summary_*.txt cspr_environment_summary_*.txt 2>/dev/null | head -n 1 || true)
        if [[ -n "${SUMMARY_FILE}" ]]; then
            BQ_PROJECT_ID=$(grep "GCP Project ID:" "${SUMMARY_FILE}" | awk '{print $NF}' || true)
        fi
    fi
    if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
        read -r -p "Customer GCP Project ID: " BQ_PROJECT_ID
    fi
fi

LOCATION="${LOCATION:-us-east1}"
PSO_SOURCE_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:v3.0.8"
FALLBACK_SOURCE_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:latest"

CUSTOMER_REPO="${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit"
CUSTOMER_TARGET_IMAGE="${CUSTOMER_REPO}/cspr-prereq:latest"
CUSTOMER_ALT_TARGET="${CUSTOMER_REPO}/cspr-toolkit-prerequisites:latest"

echo ""
echo -e "${BLUE}Configuration Summary:${NC}"
echo -e " • Target Project:     ${GREEN}${BQ_PROJECT_ID}${NC}"
echo -e " • Region:             ${GREEN}${LOCATION}${NC}"
echo -e " • Target Registry:    ${GREEN}${CUSTOMER_REPO}${NC}"
echo -e " • Source PSO Image:   ${GREEN}${PSO_SOURCE_IMAGE}${NC}"
echo ""

# 1. Check Docker availability
if ! command -v docker &> /dev/null; then
    echo -e "[ERROR] O utilitário 'docker' não foi encontrado no PATH deste ambiente."
    echo -e "Para transferir a imagem do scanner (Fase 02), você pode:"
    echo -e "  1. Executar no Google Cloud Shell (Recomendado):"
    echo -e "     No Cloud Shell da GCP, o Docker e o gcloud já vêm 100% instalados e autenticados."
    echo -e "     Basta clonar/subir este repositório e rodar: ./pso_cspr_manager.sh"
    echo -e "  2. Instalar o Docker Desktop / OrbStack localmente neste Mac para rodar na máquina local."
    exit 1
fi

# 2. Configure Docker Authentication
echo -e "${CYAN}[1/4] Configuring Docker authentication for Artifact Registry...${NC}"
gcloud auth configure-docker "us-docker.pkg.dev,${LOCATION}-docker.pkg.dev" --quiet

# 2. Pull PSO Source Image
echo -e "${CYAN}[2/4] Pulling official CSPR container image from Google Cloud PSO repo...${NC}"
if ! docker pull "${PSO_SOURCE_IMAGE}"; then
    echo -e "${YELLOW}[WARNING] Specific tag failed. Attempting latest tag...${NC}"
    docker pull "${FALLBACK_SOURCE_IMAGE}"
    PSO_SOURCE_IMAGE="${FALLBACK_SOURCE_IMAGE}"
fi
echo -e "${GREEN}[✔] Source image downloaded successfully.${NC}"

# 3. Tag Image for Customer Repository
echo -e "${CYAN}[3/4] Tagging image for customer Artifact Registry...${NC}"
docker tag "${PSO_SOURCE_IMAGE}" "${CUSTOMER_TARGET_IMAGE}"
docker tag "${PSO_SOURCE_IMAGE}" "${CUSTOMER_ALT_TARGET}"
echo " - Tagged: ${CUSTOMER_TARGET_IMAGE}"
echo " - Tagged: ${CUSTOMER_ALT_TARGET}"

# 4. Push to Customer Artifact Registry
echo -e "${CYAN}[4/4] Pushing container image to customer Artifact Registry...${NC}"
docker push "${CUSTOMER_TARGET_IMAGE}"
docker push "${CUSTOMER_ALT_TARGET}"

echo ""
echo -e "${GREEN}${BOLD}[✔] SUCCESS: CSPR Scanner Image successfully uploaded to customer repository!${NC}"
echo -e "Image URI: ${BOLD}${CUSTOMER_TARGET_IMAGE}${NC}"
echo ""
