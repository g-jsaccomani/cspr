#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 03
# Task: Deploy & Execute CSPR Prerequisite Cloud Run Job
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
echo -e "${CYAN}${BOLD} [FASE 03] Deploy & Execute CSPR Prerequisite Cloud Run Job                   ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

# 1. Parameter Resolution
SUMMARY_FILE=$(ls -t "${BASE_DIR}"/cspr_environment_summary_*.txt "${BASE_DIR}"/local_tests/cspr_environment_summary_*.txt cspr_environment_summary_*.txt 2>/dev/null | head -n 1 || true)

if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
    DEFAULT_PROJECT=""
    if [[ -n "${SUMMARY_FILE}" ]]; then
        DEFAULT_PROJECT=$(grep "GCP Project ID:" "${SUMMARY_FILE}" | awk '{print $NF}' || true)
    fi
    if [[ -n "${DEFAULT_PROJECT}" ]]; then
        read -r -p "Customer GCP Project ID [default: ${DEFAULT_PROJECT}]: " INPUT_PROJECT
        BQ_PROJECT_ID="${INPUT_PROJECT:-${DEFAULT_PROJECT}}"
    else
        read -r -p "Enter Customer GCP Project ID: " BQ_PROJECT_ID
    fi
fi

if [[ -z "${ORGANIZATION_ID:-}" ]]; then
    DEFAULT_ORG=""
    if [[ -n "${SUMMARY_FILE}" ]]; then
        DEFAULT_ORG=$(grep "Organization ID:" "${SUMMARY_FILE}" | awk '{print $NF}' || true)
    fi
    if [[ -n "${DEFAULT_ORG}" ]]; then
        read -r -p "Customer Organization ID [default: ${DEFAULT_ORG}]: " INPUT_ORG
        ORGANIZATION_ID="${INPUT_ORG:-${DEFAULT_ORG}}"
    else
        read -r -p "Enter Customer Organization ID: " ORGANIZATION_ID
    fi
fi

LOCATION="${LOCATION:-us-east1}"
GCP_GROUP_EMAIL_ADDRESS="${GCP_GROUP_EMAIL_ADDRESS:-jsaccomani@google.com}"

echo ""
echo -e "${BLUE}Job Deployment Parameters:${NC}"
echo -e " • GCP Project:        ${GREEN}${BQ_PROJECT_ID}${NC}"
echo -e " • Organization ID:    ${GREEN}${ORGANIZATION_ID}${NC}"
echo -e " • Region:             ${GREEN}${LOCATION}${NC}"
echo -e " • Security Reviewer:  ${GREEN}${GCP_GROUP_EMAIL_ADDRESS}${NC}"
echo ""

# 2. Render Processed Manifest
echo -e "${CYAN}[1/3] Generating Cloud Run Job manifest...${NC}"
PROCESSED_YAML="${BASE_DIR}/local_tests/cloudrun-job-processed-${BQ_PROJECT_ID}.yaml"
TEMPLATE_FILE="${BASE_DIR}/templates/cloudrun-prereq-job.template.yaml"

if [[ ! -f "${TEMPLATE_FILE}" ]]; then
    TEMPLATE_FILE="${BASE_DIR}/templates/cloudrun-job-v2.yaml"
fi

sed -e "s/\${BQ_PROJECT_ID}/${BQ_PROJECT_ID}/g" \
    -e "s/YOUR_CUSTOMER_PROJECT_ID/${BQ_PROJECT_ID}/g" \
    -e "s/\${ORGANIZATION_ID}/${ORGANIZATION_ID}/g" \
    -e "s/YOUR_CUSTOMER_ORG_ID/${ORGANIZATION_ID}/g" \
    -e "s/\${LOCATION}/${LOCATION}/g" \
    -e "s/us-east1/${LOCATION}/g" \
    -e "s/\${GCP_GROUP_EMAIL_ADDRESS}/${GCP_GROUP_EMAIL_ADDRESS}/g" \
    -e "s/jsaccomani@google.com/${GCP_GROUP_EMAIL_ADDRESS}/g" \
    "${TEMPLATE_FILE}" > "${PROCESSED_YAML}"

echo -e "${GREEN}[✔] Manifest generated:${NC} ${PROCESSED_YAML}"

# 3. Deploy Job Definition
echo -e "${CYAN}[2/3] Deploying Cloud Run Job definition (cspr-prereq-job)...${NC}"
gcloud run jobs replace "${PROCESSED_YAML}"     --project="${BQ_PROJECT_ID}"     --region="${LOCATION}"
echo -e "${GREEN}[✔] Job registered successfully.${NC}"

# 4. Trigger Execution (Always Async)
echo -e "${CYAN}[3/3] Triggering Cloud Run Job execution in background (--async)...${NC}"
echo "Executing: gcloud run jobs execute cspr-prereq-job --region=${LOCATION} --project=${BQ_PROJECT_ID} --async"
echo "(This initiates the collection of Cloud Asset Inventory, Org Policies, and Recommenders in background)..."
echo ""

if gcloud run jobs execute cspr-prereq-job --region="${LOCATION}" --project="${BQ_PROJECT_ID}" --async; then
    echo ""
    echo -e "${GREEN}${BOLD}[✔] SUCCESS: Cloud Run Job 'cspr-prereq-job' disparado em background (--async)!${NC}"
    echo -e "Use a ${CYAN}Opção 9${NC} no menu principal para monitorar o progresso em tempo real."
else
    echo ""
    echo -e "${YELLOW}[!] Note: Job execution reported warnings.${NC}"
    echo -e "Inspect Cloud Logging logs:"
    echo -e "https://console.cloud.google.com/run/jobs/details/${LOCATION}/cspr-prereq-job/logs?project=${BQ_PROJECT_ID}"
fi
echo ""
