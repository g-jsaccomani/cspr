#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Security Posture Review (CSPR) - Fase 05
# Task: Execute Findings Scanner, Unnest Exporter & Populate Checklist/Questionnaires
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
echo -e "${CYAN}${BOLD} [FASE 05] CSPR Findings Scanner, Data Exporter & Checklist Consolidation     ${NC}"
echo -e "${CYAN}${BOLD}==============================================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "${SCRIPT_DIR}")"
mkdir -p "${BASE_DIR}/local_tests"

if [[ -z "${BQ_PROJECT_ID:-}" ]]; then
    SUMMARY_FILE=$(ls -t "${BASE_DIR}"/cspr_environment_summary_*.txt "${BASE_DIR}"/local_tests/cspr_environment_summary_*.txt cspr_environment_summary_*.txt 2>/dev/null | grep -v "_sample.txt" | head -n 1 || true)
    DEFAULT_PROJECT=""
    if [[ -n "${SUMMARY_FILE}" ]]; then
        DEFAULT_PROJECT=$(grep "GCP Project ID:" "${SUMMARY_FILE}" | awk '{print $NF}' || true)
    fi
    DEFAULT_PROJECT="${DEFAULT_PROJECT:-nu-cspr-assessment}"
    read -r -p "Customer GCP Project ID [default: ${DEFAULT_PROJECT}]: " INPUT_PROJECT
    BQ_PROJECT_ID="${INPUT_PROJECT:-${DEFAULT_PROJECT}}"
fi

LOCATION="${LOCATION:-us-east1}"
ORGANIZATION_ID="${ORGANIZATION_ID:-802070535070}"
ORG_DOMAIN="${ORG_DOMAIN:-nubank.com.br}"

PSO_FINDINGS_IMAGE="us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/cspr-toolkit-findings:latest"
CUSTOMER_FINDINGS_IMAGE="${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-findings:latest"

# ------------------------------------------------------------------------------
# [1/5] Verify or Push CSPR Findings Image to Customer Artifact Registry
# ------------------------------------------------------------------------------
echo -e "${CYAN}[1/5] Verifying CSPR Findings container in customer Artifact Registry...${NC}"
EXISTING_IMG=$(gcloud artifacts docker images list "${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit" --project="${BQ_PROJECT_ID}" --format="value(package)" 2>/dev/null | grep "cspr-toolkit-findings" || true)

if [[ -n "${EXISTING_IMG}" ]]; then
    echo -e "${GREEN}[✔] Image '${CUSTOMER_FINDINGS_IMAGE}' already exists in customer Artifact Registry. Skipping push.${NC}"
elif command -v docker &> /dev/null; then
    echo -e "${CYAN}[i] Pulling and pushing '${PSO_FINDINGS_IMAGE}' via Docker...${NC}"
    gcloud auth configure-docker "us-docker.pkg.dev,${LOCATION}-docker.pkg.dev" --quiet
    docker pull "${PSO_FINDINGS_IMAGE}"
    docker tag "${PSO_FINDINGS_IMAGE}" "${CUSTOMER_FINDINGS_IMAGE}"
    docker push "${CUSTOMER_FINDINGS_IMAGE}"
    echo -e "${GREEN}[✔] Findings image pushed to customer registry.${NC}"
else
    echo -e "${YELLOW}[i] Local 'docker' binary not found. Transferring image via Artifact Registry HTTP V2 API...${NC}"
    python3 -c "
import subprocess, json, tempfile, os
token = subprocess.check_output(['gcloud', 'auth', 'print-access-token']).decode().strip()
src_host, src_repo = 'us-docker.pkg.dev', 'cloud-pso-security/cspr-toolkit/cspr-toolkit-findings'
dst_host, dst_repo = '${LOCATION}-docker.pkg.dev', '${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-findings'
tag = 'latest'
out = subprocess.check_output(['curl', '-sS', '-H', f'Authorization: Bearer {token}', '-H', 'Accept: application/vnd.docker.distribution.manifest.v2+json, application/vnd.oci.image.index.v1+json', f'https://{src_host}/v2/{src_repo}/manifests/{tag}'])
manifest = json.loads(out.decode())
if 'manifests' in manifest:
    amd64_digest = next((m['digest'] for m in manifest['manifests'] if m.get('platform', {}).get('architecture') == 'amd64'), manifest['manifests'][0]['digest'])
    out = subprocess.check_output(['curl', '-sS', '-H', f'Authorization: Bearer {token}', '-H', 'Accept: application/vnd.docker.distribution.manifest.v2+json', f'https://{src_host}/v2/{src_repo}/manifests/{amd64_digest}'])
    manifest = json.loads(out.decode())
blobs = [manifest['config']] + manifest.get('layers', [])
for b in blobs:
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
    echo -e "${GREEN}[✔] Findings image deployed to customer registry.${NC}"
fi

# ------------------------------------------------------------------------------
# [2/5] Ensure Cloud Identity Base Schema & Deploy/Run Findings Cloud Run Job
# ------------------------------------------------------------------------------
echo -e "${CYAN}[2/5] Ensuring Cloud Identity schema tables exist in '${BQ_PROJECT_ID}:cspr_ci'...${NC}"
bq query --nouse_legacy_sql --project_id="${BQ_PROJECT_ID}" "
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_consumers\` (name STRING, state STRING, mailsSentCount INT64, updateTime STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_domains\` (kind STRING, verified BOOL, etag STRING, creationTime STRING, isPrimary BOOL, domainName STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_groups\` (name STRING, email STRING, whoCanJoin STRING, whoCanModerateMembers STRING, whoCanViewMembership STRING, whoCanViewGroup STRING, whoCanDiscoverGroup STRING, allowExternalMembers BOOL, members ARRAY<STRUCT<email STRING>>);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_roles\` (roleAssignmentId STRING, roleId STRING, assignedTo STRING, data STRUCT<roleName STRING, roleDescription STRING, rolePrivileges ARRAY<STRUCT<privilegeName STRING, serviceId STRING>>, isSystemRole BOOL, isSuperAdminRole BOOL>);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_tokens\` (items STRING, primaryEmail STRING);
CREATE TABLE IF NOT EXISTS \`${BQ_PROJECT_ID}.cspr_ci.cloudidentity_users\` (name STRING, primaryEmail STRING, isAdmin BOOL, isDelegatedAdmin BOOL, recoveryPhone STRING, recoveryEmail STRING, isEnforcedIn2SV BOOL, isEnrolledIn2SV BOOL, suspended BOOL, lastLoginTime STRING, creationTime STRING);
" >/dev/null 2>&1 || true

PROCESSED_FINDINGS_YAML="${BASE_DIR}/local_tests/cloudrun-findings-processed-${BQ_PROJECT_ID}.yaml"
cat << EOF > "${PROCESSED_FINDINGS_YAML}"
apiVersion: run.googleapis.com/v1
kind: Job
metadata:
  name: cspr-findings-job
  labels:
    cloud.googleapis.com/location: ${LOCATION}
spec:
  template:
    spec:
      taskCount: 1
      template:
        spec:
          serviceAccountName: cspr-prereq-cloudrun-sa@${BQ_PROJECT_ID}.iam.gserviceaccount.com
          containers:
          - image: ${CUSTOMER_FINDINGS_IMAGE}
            env:
            - name: BQ_PROJECT
              value: "${BQ_PROJECT_ID}"
            - name: BQ_PROJECT_ID
              value: "${BQ_PROJECT_ID}"
            - name: BQ_BILLING_PROJECT
              value: "${BQ_PROJECT_ID}"
            - name: LOCATION
              value: "${LOCATION}"
            - name: ORGANIZATION_ID
              value: "${ORGANIZATION_ID}"
            - name: ORG_DOMAIN
              value: "${ORG_DOMAIN}"
            - name: INCLUDE_LIST
              value: ""
            - name: EXCLUDE_LIST
              value: ""
            - name: BQDATASET_INVENTORY
              value: "cspr_cai"
            - name: BQDATASET_POLICYANALYZER
              value: "cspr_policy"
            - name: BQDATASET_EFFECTIVEORGPOLICY
              value: "cspr_policy"
            - name: BQDATASET_REC
              value: "cspr_rec"
            - name: BQDATASET_FINDING
              value: "cspr_finding"
            - name: BQDATASET_CLOUDIDENTITY
              value: "cspr_ci"
            resources:
              limits:
                cpu: "4000m"
                memory: "8Gi"
          timeoutSeconds: 14400
          maxRetries: 1
EOF

echo -e "${CYAN}[2/3] Deploying and executing 'cspr-findings-job' in Cloud Run (${LOCATION}) with 4h timeout (14400s) & --async...${NC}"
gcloud run jobs replace "${PROCESSED_FINDINGS_YAML}" --project="${BQ_PROJECT_ID}" --region="${LOCATION}"
gcloud run jobs execute cspr-findings-job --project="${BQ_PROJECT_ID}" --region="${LOCATION}" --async
echo -e "${GREEN}${BOLD}[✔] Job 'cspr-findings-job' disparado em background (--async) com timeout de 4 horas (14400s)!${NC}"
echo -e "    • Use a ${CYAN}Opção 9${NC} do menu principal para acompanhar o progresso em tempo real."
echo -e "    • Quando o Job terminar (1/1 COMPLETE), use a ${CYAN}Opção 10${NC} para re-extrair o pacote final."
echo ""

# ------------------------------------------------------------------------------
# [3/3] Exportar imediatamente quaisquer Findings já presentes no BigQuery
# ------------------------------------------------------------------------------
echo -e "${CYAN}[3/3] Verificando se já existem Findings populados em '${BQ_PROJECT_ID}.cspr_finding.cspr_finding' para exportação imediata...${NC}"
export BQ_PROJECT_ID LOCATION
bash "${SCRIPT_DIR}/08_export_existing_findings.sh"

