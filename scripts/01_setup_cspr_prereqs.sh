#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Prerequisite Setup Script
# Automation for Customer Cloud Shell Execution
# Author: Joabson Saccomani (Google Cloud PSO - jsaccomani@google.com)
# ==============================================================================

set -euo pipefail

# ANSI color codes for terminal formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${CYAN}${BOLD}"
echo "=============================================================================="
echo "    Google Cloud Security Posture Review (CSPR) - Prerequisite Setup Script   "
echo "=============================================================================="
echo -e "${NC}"
echo "This script configures the dedicated GCP project, links billing, enables APIs,"
echo "creates the Artifact Registry, provisions the Service Account, and assigns"
echo "the audit roles required for the CSPR assessment."
echo ""

# ------------------------------------------------------------------------------
# 1. INTERACTIVELY COLLECT AND VALIDATE PARAMETERS
# ------------------------------------------------------------------------------

# 1.1 GCP Project Name / ID
if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
    echo -e "${YELLOW}>> [1/3] GCP Project Configuration${NC}"
    echo "Enter the dedicated GCP Project ID to create (or use an existing one)."
    echo "GCP naming rules: 6 to 30 characters, lowercase letters, digits, and hyphens."
    SUGGESTED_ID="cspr-assessment-$(date +%m%d)"
    while true; do
        read -r -p "Project Name / ID [suggestion: ${SUGGESTED_ID}]: " INPUT_PROJECT_ID
        BQ_PROJECT_ID="${INPUT_PROJECT_ID:-${SUGGESTED_ID}}"
        BQ_PROJECT_ID=$(echo "${BQ_PROJECT_ID}" | tr '[:upper:]' '[:lower:]' | xargs)
        if [[ "${BQ_PROJECT_ID}" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]]; then
            break
        else
            echo -e "${RED}Invalid ID: '${BQ_PROJECT_ID}'. Must be 6 to 30 characters, start with a letter, and contain only lowercase letters, digits, and hyphens.${NC}"
        fi
    done
fi

# 1.2 Organization ID
ORG_DISPLAY_NAME=""
if [[ -z "${ORGANIZATION_ID:-}" ]]; then
    echo ""
    echo -e "${YELLOW}>> [2/3] GCP Organization Configuration (ORG ID)${NC}"
    echo "Querying accessible organizations for your account..."
    RAW_ORGS=$(gcloud organizations list --format="value(name.basename(),displayName)" 2>/dev/null || true)
    ORGS_COUNT=$(echo "${RAW_ORGS}" | grep -c -v '^[[:space:]]*$' || true)

    if [[ "${ORGS_COUNT}" -eq 1 ]]; then
        AUTO_ORG=$(echo "${RAW_ORGS}" | awk -F'\t' '{print $1}')
        AUTO_ORG_NAME=$(echo "${RAW_ORGS}" | awk -F'\t' '{print $2}')
        echo -e "${GREEN}[✔] Auto-detected single Organization: ${BOLD}${AUTO_ORG_NAME}${NC}${GREEN} (ID: ${BOLD}${AUTO_ORG}${NC}${GREEN})${NC}"
        ORGANIZATION_ID="${AUTO_ORG}"
        ORG_DISPLAY_NAME="${AUTO_ORG_NAME}"
    elif [[ "${ORGS_COUNT}" -gt 1 ]]; then
        echo "Multiple organizations found:"
        gcloud organizations list --format="table(displayName:label=ORGANIZATION_NAME, name.basename():label=ORGANIZATION_ID)" 2>/dev/null
        FIRST_ORG=$(echo "${RAW_ORGS}" | head -n 1 | awk -F'\t' '{print $1}')
        read -r -p "Enter Organization ID [default: ${FIRST_ORG}]: " INPUT_ORG_ID
        ORGANIZATION_ID="${INPUT_ORG_ID:-${FIRST_ORG}}"
    else
        while true; do
            read -r -p "Enter Organization ID (numeric only, e.g., 31564119954): " INPUT_ORG_ID
            ORGANIZATION_ID=$(echo "${INPUT_ORG_ID}" | tr -cd '0-9')
            if [[ -n "${ORGANIZATION_ID}" ]]; then
                break
            else
                echo -e "${RED}Organization ID cannot be empty and must contain digits only.${NC}"
            fi
        done
    fi
    ORGANIZATION_ID=$(echo "${ORGANIZATION_ID}" | tr -cd '0-9')
fi

# 1.3 Billing Account ID
BILLING_DISPLAY_NAME=""
if [[ -z "${BILLING_ACCOUNT_ID:-}" ]]; then
    echo ""
    echo -e "${YELLOW}>> [3/3] Cloud Billing Account Configuration (Billing ID)${NC}"
    echo "Querying open billing accounts..."
    RAW_BILLING=$(gcloud billing accounts list --filter="open=true" --format="value(name.basename(),displayName)" 2>/dev/null || true)
    BILLING_COUNT=$(echo "${RAW_BILLING}" | grep -c -v '^[[:space:]]*$' || true)

    if [[ "${BILLING_COUNT}" -eq 1 ]]; then
        AUTO_BILLING=$(echo "${RAW_BILLING}" | awk -F'\t' '{print $1}')
        AUTO_BILLING_NAME=$(echo "${RAW_BILLING}" | awk -F'\t' '{print $2}')
        echo -e "${GREEN}[✔] Auto-detected single Billing Account: ${BOLD}${AUTO_BILLING_NAME}${NC}${GREEN} (ID: ${BOLD}${AUTO_BILLING}${NC}${GREEN})${NC}"
        BILLING_ACCOUNT_ID="${AUTO_BILLING}"
        BILLING_DISPLAY_NAME="${AUTO_BILLING_NAME}"
    elif [[ "${BILLING_COUNT}" -gt 1 ]]; then
        echo "Multiple open billing accounts found:"
        gcloud billing accounts list --filter="open=true" --format="table(name.basename():label=BILLING_ACCOUNT_ID, displayName:label=BILLING_ACCOUNT_NAME, open:label=OPEN)" 2>/dev/null
        FIRST_BILLING=$(echo "${RAW_BILLING}" | head -n 1 | awk -F'\t' '{print $1}')
        read -r -p "Enter Billing Account ID [default: ${FIRST_BILLING}]: " INPUT_BILLING_ID
        BILLING_ACCOUNT_ID="${INPUT_BILLING_ID:-${FIRST_BILLING}}"
    else
        while true; do
            read -r -p "Enter Billing Account ID (format XXXXXX-XXXXXX-XXXXXX): " INPUT_BILLING_ID
            BILLING_ACCOUNT_ID=$(echo "${INPUT_BILLING_ID}" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
            if [[ -n "${BILLING_ACCOUNT_ID}" ]]; then
                break
            else
                echo -e "${RED}Billing Account ID cannot be empty.${NC}"
            fi
        done
    fi
    BILLING_ACCOUNT_ID=$(echo "${BILLING_ACCOUNT_ID}" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
fi

# 1.4 Security Reviewer / External Access Configuration
if [[ -z "${GCP_GROUP_EMAIL_ADDRESS:-}" ]]; then
    echo ""
    echo -e "${YELLOW}>> [4/4] Security Reviewer / External Access Configuration${NC}"
    echo "Specify the email address to grant audit access (Artifact Registry & BigQuery)."
    echo "This can be a Google Cloud PSO email (e.g. jsaccomani@google.com), a customer security group,"
    echo "or an admin email. (Leave blank to use suggestion, or type 'skip' to bypass)."
    read -r -p "Reviewer Email [suggestion: jsaccomani@google.com]: " INPUT_REVIEWER_EMAIL
    if [[ "${INPUT_REVIEWER_EMAIL}" =~ ^[Ss][Kk][Ii][Pp]$ || "${INPUT_REVIEWER_EMAIL}" =~ ^[Nn][Oo][Nn][Ee]$ ]]; then
        GCP_GROUP_EMAIL_ADDRESS=""
        echo -e "${YELLOW}[INFO] External reviewer access will be skipped.${NC}"
    elif [[ -n "${INPUT_REVIEWER_EMAIL}" ]]; then
        GCP_GROUP_EMAIL_ADDRESS="${INPUT_REVIEWER_EMAIL}"
    else
        GCP_GROUP_EMAIL_ADDRESS="jsaccomani@google.com"
    fi
fi

# Supplementary default settings
LOCATION="${LOCATION:-us-east1}"

# Configuration Summary & User Confirmation
echo ""
echo -e "${BLUE}${BOLD}------------------------------------------------------------------------------"
echo "                     CONFIGURATION PARAMETERS SUMMARY                         "
echo "------------------------------------------------------------------------------${NC}"
echo -e " • GCP Project ID:         ${GREEN}${BQ_PROJECT_ID}${NC}"
if [[ -n "${ORG_DISPLAY_NAME:-}" ]]; then
    echo -e " • Organization ID:        ${GREEN}${ORGANIZATION_ID}${NC} (${ORG_DISPLAY_NAME})"
else
    echo -e " • Organization ID:        ${GREEN}${ORGANIZATION_ID}${NC}"
fi
if [[ -n "${BILLING_DISPLAY_NAME:-}" ]]; then
    echo -e " • Billing Account ID:     ${GREEN}${BILLING_ACCOUNT_ID}${NC} (${BILLING_DISPLAY_NAME})"
else
    echo -e " • Billing Account ID:     ${GREEN}${BILLING_ACCOUNT_ID}${NC}"
fi
echo -e " • Primary Region:         ${GREEN}${LOCATION}${NC}"
if [[ -n "${GCP_GROUP_EMAIL_ADDRESS}" ]]; then
    echo -e " • Security Reviewer:      ${GREEN}${GCP_GROUP_EMAIL_ADDRESS}${NC}"
else
    echo -e " • Security Reviewer:      ${YELLOW}(Skipped - configure manually later)${NC}"
fi
echo "------------------------------------------------------------------------------"
read -r -p "Confirm execution with the parameters above? [Y/n]: " CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "${CONFIRM}" =~ ^[yYsS]$ ]]; then
    echo -e "${RED}Operation cancelled by user.${NC}"
    exit 0
fi

echo ""
# ------------------------------------------------------------------------------
# 2. CREATE DEDICATED FOLDER & PROJECT & LINK BILLING
# ------------------------------------------------------------------------------
echo -e "${CYAN}[1/7] Provisioning Folder and GCP project and linking billing account...${NC}"
FOLDER_NAME="${CSPR_FOLDER_NAME:-google-cspr-audit}"
echo "Checking for existing folder '${FOLDER_NAME}' in Organization ${ORGANIZATION_ID}..."
FOLDER_ID=$(gcloud resource-manager folders list --organization="${ORGANIZATION_ID}" --filter="displayName='${FOLDER_NAME}'" --format="value(name.basename())" 2>/dev/null | head -n 1 || true)

if [[ -n "${FOLDER_ID}" ]]; then
    echo -e "${GREEN}[✔] Existing folder '${FOLDER_NAME}' found: folders/${FOLDER_ID}${NC}"
else
    echo "Creating folder '${FOLDER_NAME}' under Organization ${ORGANIZATION_ID}..."
    if FOLDER_OUTPUT=$(gcloud resource-manager folders create --display-name="${FOLDER_NAME}" --organization="${ORGANIZATION_ID}" --format="value(name.basename())" 2>&1); then
        FOLDER_ID=$(echo "${FOLDER_OUTPUT}" | tail -n 1 | tr -cd '0-9')
        echo -e "${GREEN}[✔] Created folder '${FOLDER_NAME}': folders/${FOLDER_ID}${NC}"
    else
        echo -e "${YELLOW}[WARNING] Could not create folder '${FOLDER_NAME}': ${FOLDER_OUTPUT}${NC}"
        echo -e "${YELLOW}[INFO] Proceeding to create project directly under Organization.${NC}"
        FOLDER_ID=""
    fi
fi

if gcloud projects describe "${BQ_PROJECT_ID}" &>/dev/null; then
    echo "Project '${BQ_PROJECT_ID}' already exists. Reusing existing project."
    if [[ -n "${FOLDER_ID}" ]]; then
        CURRENT_PARENT_TYPE=$(gcloud projects describe "${BQ_PROJECT_ID}" --format="value(parent.type)" 2>/dev/null || true)
        CURRENT_PARENT_ID=$(gcloud projects describe "${BQ_PROJECT_ID}" --format="value(parent.id)" 2>/dev/null || true)
        if [[ "${CURRENT_PARENT_TYPE}" == "folder" && "${CURRENT_PARENT_ID}" == "${FOLDER_ID}" ]]; then
            echo "Project '${BQ_PROJECT_ID}' is already located in folder '${FOLDER_NAME}'."
        else
            echo "Attempting to move existing project '${BQ_PROJECT_ID}' into folder '${FOLDER_NAME}' (folders/${FOLDER_ID})..."
            gcloud beta projects move "${BQ_PROJECT_ID}" --folder="${FOLDER_ID}" --quiet 2>/dev/null || {
                echo -e "${YELLOW}[INFO] Could not automatically move project to folder (requires Project Mover role). Project remains under ${CURRENT_PARENT_TYPE}/${CURRENT_PARENT_ID}.${NC}"
            }
        fi
    fi
else
    if [[ -n "${FOLDER_ID}" ]]; then
        echo "Creating project '${BQ_PROJECT_ID}' inside folder '${FOLDER_NAME}' (folders/${FOLDER_ID})..."
        gcloud projects create "${BQ_PROJECT_ID}" \
            --name="CSPR Security Assessment" \
            --folder="${FOLDER_ID}"
    else
        echo "Creating project '${BQ_PROJECT_ID}' under organization '${ORGANIZATION_ID}'..."
        gcloud projects create "${BQ_PROJECT_ID}" \
            --name="CSPR Security Assessment" \
            --organization="${ORGANIZATION_ID}"
    fi
fi

echo "Linking billing account '${BILLING_ACCOUNT_ID}' to project '${BQ_PROJECT_ID}'..."
gcloud billing projects link "${BQ_PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT_ID}"

gcloud config set project "${BQ_PROJECT_ID}" --quiet

# ------------------------------------------------------------------------------
# 3. ENABLE MANDATORY GOOGLE CLOUD APIS
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[2/7] Enabling required Google Cloud APIs...${NC}"
gcloud services enable \
  cloudasset.googleapis.com \
  bigquery.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  policyanalyzer.googleapis.com \
  recommender.googleapis.com \
  serviceusage.googleapis.com \
  --project="${BQ_PROJECT_ID}"

echo "Waiting for GCP regional service endpoints to initialize..."
sleep 5

# ------------------------------------------------------------------------------
# 4. CONFIGURE DOMAIN RESTRICTED SHARING (DRS) ORG POLICY
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[3/7] Configuring Domain Restricted Sharing (DRS) policy...${NC}"
echo "Disabling DRS constraint at project level to allow Google Cloud PSO access..."
gcloud resource-manager org-policies disable-enforce \
  constraints/iam.allowedPolicyMemberDomains \
  --project="${BQ_PROJECT_ID}" 2>/dev/null || \
  echo "[INFO] DRS constraint does not require changes or already permitted."

# ------------------------------------------------------------------------------
# 5. CREATE ARTIFACT REGISTRY REPOSITORY
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[4/7] Setting up Artifact Registry repository...${NC}"
if gcloud artifacts repositories describe customer-cspr-toolkit --location="${LOCATION}" --project="${BQ_PROJECT_ID}" &>/dev/null; then
    echo "Repository 'customer-cspr-toolkit' already exists."
else
    echo "Creating repository 'customer-cspr-toolkit' in '${LOCATION}'..."
    AR_ATTEMPT=1
    AR_MAX=6
    while [[ ${AR_ATTEMPT} -le ${AR_MAX} ]]; do
        if gcloud artifacts repositories create customer-cspr-toolkit \
          --repository-format=docker \
          --location="${LOCATION}" \
          --description="CSPR Toolkit Container Images" \
          --project="${BQ_PROJECT_ID}" 2>/dev/null; then
            echo "Artifact Registry repository successfully created."
            break
        else
            if [[ ${AR_ATTEMPT} -eq ${AR_MAX} ]]; then
                # Run with output on last attempt if it fails
                gcloud artifacts repositories create customer-cspr-toolkit \
                  --repository-format=docker \
                  --location="${LOCATION}" \
                  --description="CSPR Toolkit Container Images" \
                  --project="${BQ_PROJECT_ID}"
            fi
            echo "Artifact Registry API is still initializing in region '${LOCATION}'... Waiting 10s (attempt ${AR_ATTEMPT}/${AR_MAX})..."
            sleep 10
            AR_ATTEMPT=$((AR_ATTEMPT + 1))
        fi
    done
fi

if [[ -n "${GCP_GROUP_EMAIL_ADDRESS}" ]]; then
    echo "Ensuring Cloud Run service agent and job identities have read access to Artifact Registry..."
    PROJECT_NUMBER=$(gcloud projects describe "${BQ_PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || true)
    if [[ -n "${PROJECT_NUMBER}" ]]; then
        gcloud artifacts repositories add-iam-policy-binding customer-cspr-toolkit \
          --location="${LOCATION}" \
          --member="serviceAccount:service-${PROJECT_NUMBER}@serverless-robot-prod.iam.gserviceaccount.com" \
          --role="roles/artifactregistry.reader" \
          --project="${BQ_PROJECT_ID}" --quiet 2>/dev/null || true
    fi
    gcloud artifacts repositories add-iam-policy-binding customer-cspr-toolkit \
      --location="${LOCATION}" \
      --member="serviceAccount:cspr-prereq-cloudrun-sa@${BQ_PROJECT_ID}.iam.gserviceaccount.com" \
      --role="roles/artifactregistry.reader" \
      --project="${BQ_PROJECT_ID}" --quiet 2>/dev/null || true

    echo "Granting Artifact Registry Writer role to '${GCP_GROUP_EMAIL_ADDRESS}'..."
    AR_OUTPUT=$(gcloud artifacts repositories add-iam-policy-binding customer-cspr-toolkit \
      --location="${LOCATION}" \
      --member="user:${GCP_GROUP_EMAIL_ADDRESS}" \
      --role="roles/artifactregistry.writer" \
      --project="${BQ_PROJECT_ID}" --quiet 2>&1) || {
        if echo "${AR_OUTPUT}" | grep -q "allowedPolicyMemberDomains"; then
            echo -e "${YELLOW}[WARNING] Could not grant Artifact Registry Writer to '${GCP_GROUP_EMAIL_ADDRESS}' due to Domain Restricted Sharing (DRS) policy.${NC}"
            echo -e "${YELLOW}[ACTION] If '${GCP_GROUP_EMAIL_ADDRESS}' is outside permitted domains, your Org Admin can add an exemption, or grant access later.${NC}"
        else
            echo -e "${YELLOW}[WARNING] Could not grant Artifact Registry Writer to '${GCP_GROUP_EMAIL_ADDRESS}': ${AR_OUTPUT}${NC}"
        fi
    }
else
    echo -e "${YELLOW}[INFO] Artifact Registry reviewer access skipped as requested.${NC}"
fi

# ------------------------------------------------------------------------------
# 6. SERVICE ACCOUNT & AUDIT IAM ROLE BINDINGS (PROJECT & ORGANIZATION)
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[5/7] Provisioning Service Account and binding audit roles...${NC}"
SA_NAME="cspr-prereq-cloudrun-sa"
SA_EMAIL="${SA_NAME}@${BQ_PROJECT_ID}.iam.gserviceaccount.com"

if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${BQ_PROJECT_ID}" &>/dev/null; then
    echo "Service Account '${SA_EMAIL}' already exists."
else
    echo "Creating service account '${SA_NAME}'..."
    gcloud iam service-accounts create "${SA_NAME}" \
      --description="Service Account executing the CSPR Toolkit Cloud Run Job" \
      --display-name="cspr_toolkit_cloudrun_sa" \
      --project="${BQ_PROJECT_ID}"
    echo "Waiting 10s for IAM Service Account propagation across GCP..."
    sleep 10
fi

echo "Assigning Project-level permissions to the Service Account..."
PROJECT_SA_ROLES=(
  "roles/bigquery.admin"
  "roles/resourcemanager.projectMover"
  "roles/iam.serviceAccountTokenCreator"
)

for role in "${PROJECT_SA_ROLES[@]}"; do
    echo " - Binding ${role}..."
    SA_ATTEMPT=1
    while [[ ${SA_ATTEMPT} -le 6 ]]; do
        if gcloud projects add-iam-policy-binding "${BQ_PROJECT_ID}" \
          --member="serviceAccount:${SA_EMAIL}" \
          --role="${role}" --quiet &>/dev/null; then
            break
        fi
        echo "   Waiting for Service Account IAM propagation (attempt ${SA_ATTEMPT}/6)..."
        sleep 5
        SA_ATTEMPT=$((SA_ATTEMPT + 1))
    done
    if [[ ${SA_ATTEMPT} -gt 6 ]]; then
        gcloud projects add-iam-policy-binding "${BQ_PROJECT_ID}" \
          --member="serviceAccount:${SA_EMAIL}" \
          --role="${role}" --quiet
    fi
done

echo "Assigning Organization-level read permissions (${ORGANIZATION_ID})..."
ORG_ROLES=(
  "roles/cloudasset.viewer"
  "roles/resourcemanager.folderViewer"
  "roles/resourcemanager.organizationViewer"
  "roles/orgpolicy.policyViewer"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/policyanalyzer.activityAnalysisViewer"
  "roles/recommender.exporter"
)

for role in "${ORG_ROLES[@]}"; do
  echo " - Binding ${role}..."
  gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${role}" --quiet
done

# ------------------------------------------------------------------------------
# 7. PROCESS MANIFEST & PREPARE CLOUD RUN JOB
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[6/7] Processing manifest and preparing Cloud Run Job...${NC}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_TEMPLATE="${SCRIPT_DIR}/cloudrun-job-v2.yaml"
PROCESSED_YAML="/tmp/cloudrun-job-processed-${BQ_PROJECT_ID}.yaml"

if [[ -f "${YAML_TEMPLATE}" ]]; then
    echo "Generating Cloud Run manifest from template '${YAML_TEMPLATE}'..."
    sed -e "s/YOUR_CUSTOMER_PROJECT_ID/${BQ_PROJECT_ID}/g" \
        -e "s/YOUR_CUSTOMER_ORG_ID/${ORGANIZATION_ID}/g" \
        -e "s/us-east1/${LOCATION}/g" \
        -e "s/jsaccomani@google.com/${GCP_GROUP_EMAIL_ADDRESS}/g" \
        "${YAML_TEMPLATE}" > "${PROCESSED_YAML}"
else
    echo "Generating Cloud Run manifest dynamically..."
    cat <<EOF > "${PROCESSED_YAML}"
apiVersion: run.googleapis.com/v1
kind: Job
metadata:
  name: cspr-prereq-job
  labels:
    cloud.googleapis.com/location: ${LOCATION}
spec:
  template:
    spec:
      taskCount: 1
      template:
        spec:
          serviceAccountName: ${SA_EMAIL}
          containers:
          - image: ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-prereq:latest
            env:
            - name: BQ_PROJECT_ID
              value: "${BQ_PROJECT_ID}"
            - name: ORGANIZATION_ID
              value: "${ORGANIZATION_ID}"
            - name: LOCATION
              value: "${LOCATION}"
            - name: GCP_GROUP_EMAIL_ADDRESS
              value: "${GCP_GROUP_EMAIL_ADDRESS}"
            - name: ENABLE_CAI
              value: "TRUE"
            - name: ENABLE_ORGPOLICY
              value: "TRUE"
            - name: ENABLE_RECOMMENDER_EXPORT
              value: "TRUE"
            - name: ENABLE_SAKEY_ANALYZER
              value: "TRUE"
            resources:
              limits:
                cpu: "2000m"
                memory: "4Gi"
          timeoutSeconds: 3600
          maxRetries: 1
EOF
fi

cp "${PROCESSED_YAML}" "${SCRIPT_DIR}/cloudrun-job-processed.yaml" 2>/dev/null || true
echo -e "${GREEN}[✔] Cloud Run Job manifest generated:${NC} cloudrun-job-processed.yaml"

echo "Checking if container image is already available in Artifact Registry..."
if gcloud artifacts docker images list "${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit" --include-tags --format="value(TAGS)" 2>/dev/null | grep -q "latest"; then
    echo "Container image detected! Deploying and triggering Cloud Run Job..."
    gcloud run jobs replace "${PROCESSED_YAML}" --project="${BQ_PROJECT_ID}" --region="${LOCATION}"
    gcloud run jobs execute cspr-prereq-job --project="${BQ_PROJECT_ID}" --region="${LOCATION}" --wait
else
    echo -e "${YELLOW}[INFO] Container image has not yet been pushed to Artifact Registry.${NC}"
    echo -e "${YELLOW}[INFO] Google Cloud PSO (${GCP_GROUP_EMAIL_ADDRESS}) will push the scanner image and deploy/execute the Cloud Run Job.${NC}"
fi

# ------------------------------------------------------------------------------
# 8. GRANT ACCESS PERMISSIONS TO GOOGLE CLOUD PSO
# ------------------------------------------------------------------------------
echo ""
echo -e "${CYAN}[7/7] Granting BigQuery and Logging permissions to Security Reviewer...${NC}"
REVIEWER_ACCESS_STATUS="[✔] Granted"
if [[ -n "${GCP_GROUP_EMAIL_ADDRESS}" ]]; then
    PSO_ROLES=(
      "roles/bigquery.dataEditor"
      "roles/bigquery.user"
      "roles/logging.viewer"
      "roles/serviceusage.serviceUsageConsumer"
      "roles/run.admin"
      "roles/iam.serviceAccountUser"
    )

    for role in "${PSO_ROLES[@]}"; do
      echo " - Binding ${role} to ${GCP_GROUP_EMAIL_ADDRESS}..."
      PSO_OUTPUT=$(gcloud projects add-iam-policy-binding "${BQ_PROJECT_ID}" \
        --member="user:${GCP_GROUP_EMAIL_ADDRESS}" \
        --role="${role}" --quiet 2>&1) || {
          if echo "${PSO_OUTPUT}" | grep -q "allowedPolicyMemberDomains"; then
              echo -e "${YELLOW}[WARNING] Could not grant ${role} to '${GCP_GROUP_EMAIL_ADDRESS}' due to Domain Restricted Sharing (DRS).${NC}"
              REVIEWER_ACCESS_STATUS="[!] Pending DRS exemption"
          else
              echo -e "${YELLOW}[WARNING] Could not grant ${role}: ${PSO_OUTPUT}${NC}"
              REVIEWER_ACCESS_STATUS="[!] Requires manual IAM grant"
          fi
      }
    done
else
    echo -e "${YELLOW}[INFO] Security Reviewer permissions skipped as requested.${NC}"
    REVIEWER_ACCESS_STATUS="[-] Skipped by user"
fi

# ------------------------------------------------------------------------------
# 9. GENERATE CONNECTION SUMMARY OUTPUT FOR JOABSON SACCOMANI
# ------------------------------------------------------------------------------
PROJECT_NUMBER=$(gcloud projects describe "${BQ_PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || echo "N/A")
EXECUTED_BY=$(gcloud config get-value account 2>/dev/null || echo "Cloud Shell User")
EXEC_TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
OUTPUT_FILE="${PWD}/cspr_environment_summary_${BQ_PROJECT_ID}.txt"

REVIEWER_DISPLAY="${GCP_GROUP_EMAIL_ADDRESS:-None (Configure manually later)}"
if [[ -n "${FOLDER_ID}" ]]; then
    FOLDER_DISPLAY="folders/${FOLDER_ID}"
else
    FOLDER_DISPLAY="Organization Root"
fi

SUMMARY_TEXT=$(cat <<EOF
========================================================================================
📋 CSPR ENVIRONMENT REPORT - CONNECTION DETAILS (GOOGLE CLOUD PSO)
========================================================================================
Execution Date:  ${EXEC_TIMESTAMP}
Executed By:     ${EXECUTED_BY}
Security Lead:   Joabson Saccomani (jsaccomani@google.com)

----------------------------------------------------------------------------------------
1. PROVISIONED ENVIRONMENT DETAILS:
----------------------------------------------------------------------------------------
 • GCP Project ID:         ${BQ_PROJECT_ID}
 • GCP Project Number:     ${PROJECT_NUMBER}
 • Organization ID:        ${ORGANIZATION_ID}
 • Parent Folder:          ${FOLDER_NAME} (${FOLDER_DISPLAY})
 • Billing Account ID:     ${BILLING_ACCOUNT_ID}
 • Primary Region:         ${LOCATION}
 • Service Account:        ${SA_EMAIL}
 • Artifact Registry:      ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit
 • Cloud Run Job:          cspr-prereq-job
 • Security Reviewer:      ${REVIEWER_DISPLAY} (${REVIEWER_ACCESS_STATUS})

----------------------------------------------------------------------------------------
2. GOOGLE CLOUD PSO CONNECTION & EXECUTION COMMANDS:
----------------------------------------------------------------------------------------
# Step A: Set target project:
gcloud config set project ${BQ_PROJECT_ID}

# Step B: Push CSPR scanner image to customer's Artifact Registry:
gcloud auth configure-docker ${LOCATION}-docker.pkg.dev --quiet
docker pull us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:v3.0.8
docker tag us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-prerequisites:v3.0.8 ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-prereq:latest
docker push ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-prereq:latest

# Step C: Deploy and execute Cloud Run Job:
gcloud run jobs replace cloudrun-job-processed.yaml --project=${BQ_PROJECT_ID} --region=${LOCATION}
gcloud run jobs execute cspr-prereq-job --region=${LOCATION} --project=${BQ_PROJECT_ID}

# Step D: Verify BigQuery datasets creation:
bq ls --project_id=${BQ_PROJECT_ID}

----------------------------------------------------------------------------------------
3. PREREQUISITES VALIDATION CHECKLIST:
----------------------------------------------------------------------------------------
 [✔] Organization Folder verified/created (${FOLDER_NAME}: ${FOLDER_DISPLAY})
 [✔] GCP Project provisioned and billing account linked (${BILLING_ACCOUNT_ID})
 [✔] 7 mandatory APIs enabled (Cloud Asset, BigQuery, Run, Artifact Registry, etc.)
 [✔] Artifact Registry repository created (customer-cspr-toolkit)
 [✔] Service Account created with Project and Organization level viewer roles
 [✔] Cloud Run Job definition deployed with proper variable substitution
 ${REVIEWER_ACCESS_STATUS} Reviewer permissions (${REVIEWER_DISPLAY})

⚠️  TELEMETRY INGESTION WINDOW:
 Recommender and Policy Analyzer data require 48 to 72 hours for complete
 backend ingestion into BigQuery after the Job execution.
========================================================================================
EOF
)

# Print prominent summary block to terminal
echo ""
echo -e "${GREEN}${BOLD}${SUMMARY_TEXT}${NC}"
echo ""

# Save local copy in current directory
echo "${SUMMARY_TEXT}" > "${OUTPUT_FILE}"
echo -e "${YELLOW}💾 A copy of this report was saved to:${NC} ${BOLD}${OUTPUT_FILE}${NC}"
echo -e "${CYAN}Please copy the block above and send it to ${BOLD}jsaccomani@google.com${NC} or via Slack.${NC}"
echo ""

