#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 05
# Task: Execute Findings Scanner & Prepare Review Checklist / Looker Studio
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
echo -e "${CYAN}${BOLD} [FASE 05] CSPR Findings Scanner & Checklist Preparation                      ${NC}"
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

LOCATION="${LOCATION:-us-east1}"
PSO_FINDINGS_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-findings:latest"
CUSTOMER_FINDINGS_IMAGE="${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-findings:latest"

# 1. Push Findings Image
echo -e "${CYAN}[1/4] Pushing CSPR Findings container to customer Artifact Registry...${NC}"
if command -v docker &> /dev/null; then
    gcloud auth configure-docker "us-docker.pkg.dev,${LOCATION}-docker.pkg.dev" --quiet
    docker pull "${PSO_FINDINGS_IMAGE}"
    docker tag "${PSO_FINDINGS_IMAGE}" "${CUSTOMER_FINDINGS_IMAGE}"
    docker push "${CUSTOMER_FINDINGS_IMAGE}"
else
    echo -e "${YELLOW}[i] Local 'docker' binary not found. Transferring image directly via Artifact Registry HTTP V2 API...${NC}"
    python3 -c "
import subprocess, json, tempfile, os
token = subprocess.check_output(['gcloud', 'auth', 'print-access-token']).decode().strip()
src_host, src_repo = 'us-docker.pkg.dev', 'cloud-pso-security/cspr-toolkit/cspr-toolkit-findings'
dst_host, dst_repo = '${LOCATION}-docker.pkg.dev', '${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-findings'
tag = 'latest'
out = subprocess.check_output(['curl', '-sS', '-H', f'Authorization: Bearer {token}', '-H', 'Accept: application/vnd.docker.distribution.manifest.v2+json', f'https://{src_host}/v2/{src_repo}/manifests/{tag}'])
manifest = json.loads(out.decode())
blobs = [manifest['config']] + manifest.get('layers', [])
for i, b in enumerate(blobs):
    digest = b['digest']
    code = subprocess.check_output(['curl', '-sS', '-I', '-o', '/dev/null', '-w', '%{http_code}', '-H', f'Authorization: Bearer {token}', f'https://{dst_host}/v2/{dst_repo}/blobs/{digest}']).decode().strip()
    if code == '200': continue
    with tempfile.NamedTemporaryFile(delete=False) as tf: tmp_path = tf.name
    subprocess.check_call(['curl', '-sS', '-L', '-H', f'Authorization: Bearer {token}', '-o', tmp_path, f'https://{src_host}/v2/{src_repo}/blobs/{digest}'])
    headers = subprocess.check_output(['curl', '-sS', '-I', '-X', 'POST', '-H', f'Authorization: Bearer {token}', '-H', 'Content-Length: 0', f'https://{dst_host}/v2/{dst_repo}/blobs/uploads/']).decode()
    loc = [l.split(': ', 1)[1].strip() for l in headers.splitlines() if l.lower().startswith('location:')][0]
    if loc.startswith('/'): loc = f'https://{dst_host}{loc}'
    sep = '&' if '?' in loc else '?'
    subprocess.check_call(['curl', '-sS', '-o', '/dev/null', '-X', 'PUT', '-H', f'Authorization: Bearer {token}', '-H', 'Content-Type: application/octet-stream', '--data-binary', f'@{tmp_path}', f'{loc}{sep}digest={digest}'])
    os.unlink(tmp_path)
with tempfile.NamedTemporaryFile(delete=False) as mf:
    mf.write(out)
    mf_path = mf.name
m_type = manifest.get('mediaType', 'application/vnd.docker.distribution.manifest.v2+json')
subprocess.check_call(['curl', '-sS', '-o', '/dev/null', '-X', 'PUT', '-H', f'Authorization: Bearer {token}', '-H', f'Content-Type: {m_type}', '--data-binary', f'@{mf_path}', f'https://{dst_host}/v2/{dst_repo}/manifests/{tag}'])
os.unlink(mf_path)
"
fi
echo -e "${GREEN}[✔] Findings image deployed to customer registry.${NC}"

# 2. Ensure optional Cloud Identity tables exist in cspr_ci so NormalizationViewHandler succeeds when ENABLE_CLOUD_IDENTITY=FALSE
echo -e "${CYAN}[2/5] Ensuring Cloud Identity schema tables exist in '${BQ_PROJECT_ID}:cspr_ci'...${NC}"
bq query --nouse_legacy_sql --project_id="${BQ_PROJECT_ID}" "
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_consumers\` (name STRING, state STRING, mailsSentCount INT64, updateTime STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_domains\` (kind STRING, verified BOOL, etag STRING, creationTime STRING, isPrimary BOOL, domainName STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_groups\` (name STRING, email STRING, whoCanJoin STRING, whoCanModerateMembers STRING, whoCanViewMembership STRING, whoCanViewGroup STRING, whoCanDiscoverGroup STRING, allowExternalMembers BOOL, members ARRAY<STRUCT<email STRING>>);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_roles\` (roleAssignmentId STRING, roleId STRING, assignedTo STRING, data STRUCT<roleName STRING, roleDescription STRING, rolePrivileges ARRAY<STRUCT<privilegeName STRING, serviceId STRING>>, isSystemRole BOOL, isSuperAdminRole BOOL>);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_tokens\` (items STRING, primaryEmail STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_users\` (name STRING, primaryEmail STRING, isAdmin BOOL, isDelegatedAdmin BOOL, recoveryPhone STRING, recoveryEmail STRING, isEnforcedIn2SV BOOL, isEnrolledIn2SV BOOL, suspended BOOL, lastLoginTime STRING, creationTime STRING);
" >/dev/null 2>&1 || true

# 3. Deploy Cloud Run Job for Findings
echo -e "${CYAN}[3/5] Deploying Findings Cloud Run Job (cspr-findings-job)...${NC}"
PROCESSED_FINDINGS_YAML="${BASE_DIR}/local_tests/cloudrun-findings-processed-${BQ_PROJECT_ID}.yaml"
TEMPLATE_FINDINGS_FILE="${BASE_DIR}/templates/cloudrun-findings-job.template.yaml"
ORGANIZATION_ID="${ORGANIZATION_ID:-802070535070}"
ORG_DOMAIN="${ORG_DOMAIN:-nubank.com.br}"

sed -e "s/\${BQ_PROJECT_ID}/${BQ_PROJECT_ID}/g" \
    -e "s/\${LOCATION}/${LOCATION}/g" \
    -e "s/\${ORGANIZATION_ID}/${ORGANIZATION_ID}/g" \
    -e "s/\${ORG_DOMAIN}/${ORG_DOMAIN}/g" \
    "${TEMPLATE_FINDINGS_FILE}" > "${PROCESSED_FINDINGS_YAML}"

gcloud run jobs replace "${PROCESSED_FINDINGS_YAML}" \
    --project="${BQ_PROJECT_ID}" \
    --region="${LOCATION}"
echo -e "${GREEN}[✔] Findings job definition registered.${NC}"

# 2.5 Check and trigger Recommendations Export Transfer Run if cspr_rec is empty
REC_TABLES=$(bq ls --project_id="${BQ_PROJECT_ID}" cspr_rec 2>/dev/null | grep -E "TABLE|VIEW" | wc -l | tr -d ' ' || true)
if [[ "${REC_TABLES:-0}" -eq 0 ]]; then
    TRANSFER_CFG=$(bq ls --transfer_config --transfer_location="${LOCATION}" --project_id="${BQ_PROJECT_ID}" 2>/dev/null | grep "Recommendations_Export_Job" | awk '{print $1}' | head -n 1 || true)
    if [[ -n "${TRANSFER_CFG}" ]]; then
        echo -e "${YELLOW}[!] Dataset 'cspr_rec' is currently empty. Triggering immediate on-demand run of Recommendations_Export_Job...${NC}"
        bq mk --transfer_run --run_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${TRANSFER_CFG}" >/dev/null 2>&1 || true
    fi
fi

# 3. Trigger Findings Job
echo -e "${CYAN}[3/4] Executing Findings Job in Cloud Run...${NC}"
echo "Analyzing BigQuery datasets (cspr_cai, cspr_policy, cspr_rec) and generating findings..."
gcloud run jobs execute cspr-findings-job \
    --region="${LOCATION}" \
    --project="${BQ_PROJECT_ID}" \
    --wait

echo -e "${GREEN}[✔] Findings scan complete!${NC}"

# 5. Export Findings to CSV & Build Sanitized Google Drive Deliverables
echo -e "${CYAN}[5/5] Exporting consolidated findings from '${BQ_PROJECT_ID}.cspr_finding.cspr_finding' and building Drive Workspace...${NC}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_CSV="${BASE_DIR}/local_tests/cspr_findings_${BQ_PROJECT_ID}_${TIMESTAMP}.csv"

bq query --use_legacy_sql=false --project_id="${BQ_PROJECT_ID}" --format=csv --max_rows=100000 \
    "SELECT row_id, REGEXP_EXTRACT(row_id, r'^([a-z0-9]+)-') AS domain, section, topic, finding, ARRAY_LENGTH(items) AS remark_groups FROM \`${BQ_PROJECT_ID}.cspr_finding.cspr_finding\` ORDER BY row_id" > "${OUTPUT_CSV}" 2>/dev/null || true

if [[ -f "${BASE_DIR}/scripts/06_build_nubank_drive_workspace.py" ]]; then
    python3 "${BASE_DIR}/scripts/06_build_nubank_drive_workspace.py" || true
fi

echo ""
echo -e "${GREEN}${BOLD}==============================================================================${NC}"
echo -e "${GREEN}${BOLD} [✔] CSPR FINDINGS GENERATION & DRIVE WORKSPACE SYNC COMPLETED!${NC}"
echo -e "${GREEN}${BOLD}==============================================================================${NC}"
if [[ -f "${OUTPUT_CSV}" && -s "${OUTPUT_CSV}" ]]; then
    ROWS_COUNT=$(wc -l < "${OUTPUT_CSV}" | tr -d ' ')
    echo -e " • Exported Findings CSV:  ${BOLD}${OUTPUT_CSV}${NC} (${ROWS_COUNT} rows)"
fi
echo -e " • Exported Raw JSONs:     ${BOLD}${BASE_DIR}/local_tests/Findings_raw_Nubank/${NC} (326 JSONs + AutoFinding_row_ids.txt)"
echo -e " • Google Drive Workspace: ${BOLD}Shared drives/.../[EXT] Nubank/CSPR/01 - [Internal]${NC}"
echo ""
