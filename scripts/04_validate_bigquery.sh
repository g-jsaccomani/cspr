#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 04
# Task: Validate BigQuery Datasets and Ingestion Telemetry (CAI, Policy, Rec)
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
echo -e "${CYAN}${BOLD} [FASE 04] BigQuery Datasets & Telemetry Validation                           ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"

if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
    SUMMARY_FILE=$(ls -t "${BASE_DIR}"/cspr_environment_summary_*.txt "${BASE_DIR}"/local_tests/cspr_environment_summary_*.txt cspr_environment_summary_*.txt 2>/dev/null | head -n 1 || true)
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

echo ""
echo -e "Querying BigQuery datasets in project: ${BOLD}${BQ_PROJECT_ID}${NC}..."
BQ_ERR=$(mktemp)
if ! DATASETS=$(bq ls --project_id="${BQ_PROJECT_ID}" --format=prettyjson 2>"${BQ_ERR}"); then
    echo ""
    echo -e "${RED}[✘] Failed to query BigQuery in project '${BQ_PROJECT_ID}'.${NC}"
    echo -e "${YELLOW}Details:${NC}"
    cat "${BQ_ERR}"
    rm -f "${BQ_ERR}"
    echo ""
    echo -e "${CYAN}Tip:${NC} Make sure you are authenticated with the Nubank account (${BOLD}gcloud auth login${NC}) or run inside Cloud Shell."
    exit 1
fi
rm -f "${BQ_ERR}"

check_dataset() {
    local DATASET_NAME="$1"
    local DESCRIPTION="$2"
    local IS_ASYNC="$3"
    
    echo -n " • Checking dataset '${DATASET_NAME}' (${DESCRIPTION})... "
    if echo "${DATASETS}" | grep -q "\"${DATASET_NAME}\""; then
        TABLES_COUNT=$(bq ls --project_id="${BQ_PROJECT_ID}" "${DATASET_NAME}" 2>/dev/null | grep -c -E "TABLE|VIEW" || true)
        echo -e "${GREEN}[✔] Present (${TABLES_COUNT} tables/views)${NC}"
    else
        if [[ "${IS_ASYNC}" == "true" ]]; then
            echo -e "${YELLOW}[⏳] Pending Ingestion (48h-72h window)${NC}"
        else
            echo -e "${RED}[✗] Not found (or Job still running)${NC}"
        fi
    fi
}

echo ""
echo -e "${BOLD}--- BigQuery Datasets Verification ---${NC}"
check_dataset "cspr_cai" "Cloud Asset Inventory" "false"
check_dataset "cspr_policy" "Organization Policies & Key Analyzer" "false"
check_dataset "cspr_rec" "Security & IAM Recommenders" "true"
check_dataset "cspr_finding" "CSPR Findings (Scanner Output)" "true"
check_dataset "cspr_ci" "Cloud Identity (Optional)" "true"

echo ""
echo -e "${BOLD}--- Table Rows Verification ---${NC}"

check_table_rows() {
    local DATASET="$1"
    local TABLE="$2"
    local QUERY="SELECT count(1) FROM \`${BQ_PROJECT_ID}.${DATASET}.${TABLE}\`"
    
    local COUNT
    COUNT=$(bq query --nouse_legacy_sql --format=csv --quiet "${QUERY}" 2>/dev/null | tail -n 1 || true)
    if [[ -n "${COUNT}" && "${COUNT}" =~ ^[0-9]+$ ]]; then
        echo -e " • ${DATASET}.${TABLE}: ${GREEN}${COUNT} rows${NC}"
    else
        echo -e " • ${DATASET}.${TABLE}: ${YELLOW}(Table not ready or empty)${NC}"
    fi
}

check_table_rows "cspr_cai" "iam_policy"
check_table_rows "cspr_cai" "org_policy"
check_table_rows "cspr_policy" "policyanalyzer_orgpolicy_analysis"
check_table_rows "cspr_policy" "policyanalyzer_UnusedServiceAccountKey"

echo ""
echo -e "${CYAN}${BOLD}==============================================================================${NC}"
echo -e "${YELLOW}${BOLD} ⚠️  CRITICAL TELEMETRY INGESTION WINDOW (48 - 72h):${NC}"
echo -e " Cloud Asset Inventory (cspr_cai) and Org Policies (cspr_policy) populate immediately."
echo -e " Google Cloud Recommenders and Insights (cspr_rec) require 48 to 72 hours for complete"
echo -e " historical consolidation into BigQuery per Google Cloud architecture."
echo -e "${CYAN}${BOLD}==============================================================================${NC}"
echo ""
