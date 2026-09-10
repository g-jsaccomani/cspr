# Cloud Security Posture Review (CSPR)
## PSO Post-Setup Technical Execution Runbook & Operational Guide

**Client:** <CUSTOMER_ORGANIZATION>  
**Lead Architect:** Joabson Saccomani (Google Cloud PSO Lead - jsaccomani@google.com)  
**Engagement Framework:** Google Cloud Security Posture Review v3.0  
**Phase:** Post-Setup Execution, Telemetry Consolidation & Findings Analysis  

---

## 1. Executive Summary & Operational Context

Once Customer's Cloud Security team completes Steps 1 & 2 using the automated setup script (`setup_cspr_prereqs-v2.sh` or `scripts/01_setup_cspr_prereqs.sh`) and provides the connection report block (`cspr_environment_summary_<PROJECT_ID>.txt`), the execution lifecycle transitions entirely to the **Google Cloud PSO team**.

All scanning operations, dataset consolidations, and security evaluations execute within **Customer's dedicated, isolated GCP project**. Data is never exported outside Customer's tenant boundaries. Google Cloud PSO operates with least-privilege access restricted to container deployment, Cloud Run Job execution, and BigQuery analysis.

```
+---------------------------------------------------------------------------------------------------+
|                                CUSTOMER DEDICATED GCP AUDIT TENANT                                |
|                                                                                                   |
|  [Google Cloud PSO]                                                                               |
|         │                                                                                         |
|         ├─► [1. Docker Push] ─────────► [Artifact Registry] (customer-cspr-toolkit)               |
|         │                                       │                                                 |
|         ├─► [2. Deploy & Run Job] ───► [Cloud Run Job] (cspr-prereq-job)                          |
|         │                                       │                                                 |
|         │                                (Exports Data)                                           |
|         │                                       ▼                                                 |
|         ├─► [3. BigQuery Validation] ─► [BigQuery Datasets]                                       |
|         │                                ├── cspr_cai (Immediate: Assets & IAM)                   |
|         │                                ├── cspr_policy (Immediate: Org Policies & Keys)         |
|         │                                └── cspr_rec (48-72h: Security & IAM Recommenders)       |
|         │                                       │                                                 |
|         └─► [4. Findings Scan] ──────► [cspr_finding Dataset] ──► [Looker Studio & Review Doc]    |
+---------------------------------------------------------------------------------------------------+
```

---

## 2. Interactive CLI Orchestrator: `pso_cspr_manager.sh`

To eliminate manual parameter typing and streamline all 4 post-setup operations, the repository provides a unified terminal manager:

```bash
./pso_cspr_manager.sh
```

The script automatically detects the provisioned project from `cspr_environment_summary_*.txt` and provides an interactive menu:
1. **[Step 1]** Push CSPR Scanner Image to Customer Artifact Registry
2. **[Step 2]** Deploy & Execute Cloud Run Job (Start Data Collection)
3. **[Step 3]** Validate BigQuery Datasets & Tables (CAI, Policy, Recommenders)
4. **[Step 4]** Run CSPR Findings Scanner & Export to CSV / Looker Studio
5. **[Pipeline]** Run Steps 1 -> 3 Sequentially (Immediate Full Ingestion)

---

## 3. Step-by-Step Technical Execution Blueprint

### 3.1 Step 1: Upload Scanner Image to Customer Artifact Registry

Because the CSPR container images are proprietary to Google Cloud PSO, Customer cannot pull directly from `us-docker.pkg.dev/cloud-pso-security/...`. The Google Cloud PSO engineer pulls the image with `@google.com` credentials and pushes it into Customer's dedicated repository.

#### Automated Execution:
```bash
./scripts/02_push_scanner_image.sh
# or via Cloud Shell: ./scripts/01.1_cloudshell_push_image.sh
```

#### Manual Commands:
```bash
export BQ_PROJECT_ID="<CUSTOMER_PROJECT_ID>"
export LOCATION="us-east1"
export IMAGE="cspr-toolkit-prerequisites:v3.0.8"

# Authenticate Docker
gcloud auth configure-docker us-docker.pkg.dev,${LOCATION}-docker.pkg.dev --quiet

# Pull from Google PSO repository
docker pull us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/${IMAGE}

# Tag for Customer's Artifact Registry
docker tag us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/${IMAGE} \
  ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-prereq:latest

docker tag us-docker.pkg.dev/cloud-pso-security/cspr-toolkit/${IMAGE} \
  ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-prerequisites:latest

# Push to customer repository
docker push ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-prereq:latest
docker push ${LOCATION}-docker.pkg.dev/${BQ_PROJECT_ID}/customer-cspr-toolkit/cspr-toolkit-prerequisites:latest
```

---

### 3.2 Step 2: Deploy and Trigger Cloud Run Job

Once the container image is in the Artifact Registry, the Cloud Run Job can be registered and triggered. It executes under the service account identity `cspr-prereq-cloudrun-sa@${BQ_PROJECT_ID}.iam.gserviceaccount.com`.

#### Automated Execution:
```bash
./scripts/03_deploy_and_run_job.sh
```

#### Manual Commands:
```bash
# Deploy / Update the Cloud Run Job
gcloud run jobs replace cloudrun-job-processed.yaml \
  --project=${BQ_PROJECT_ID} \
  --region=${LOCATION}

# Execute the Job and stream execution logs
gcloud run jobs execute cspr-prereq-job \
  --region=${LOCATION} \
  --project=${BQ_PROJECT_ID} \
  --wait
```

---

### 3.3 Step 3: BigQuery Dataset Validation & 48-72h Telemetry Window

#### Telemetry Ingestion Timing Architecture:
* **Immediate (0 - 2 hours):**
  * `cspr_cai`: Full Cloud Asset Inventory topology (compute, storage, IAM allow policies, firewalls, VPC networks).
  * `cspr_policy`: Active and effective Organization Policies, Service Account Key analysis.
* **Asynchronous (48 - 72 hours):**
  * `cspr_rec`: Google Cloud Recommenders (Security Command Center, IAM over-granting, Idle resources). Google Cloud Recommender daily export routines require 48 to 72 hours to ingest historical and cross-project recommendations into BigQuery.

#### Automated Dataset Verification:
```bash
./scripts/04_validate_bigquery.sh
```

#### SQL Validation Queries (available under `sql/`):
```bash
# 1. Verify Cloud Asset Inventory resources
bq query --use_legacy_sql=false < sql/01_validate_cai_assets.sql

# 2. Verify Organization Policies
bq query --use_legacy_sql=false < sql/02_validate_org_policies.sql

# 3. Verify Recommender telemetry
bq query --use_legacy_sql=false < sql/03_validate_recommenders.sql
```

---

### 3.4 Step 4: Execute Findings Scanner & Prepare Discovery Workshop Assets

Once BigQuery telemetry is consolidated, Google Cloud PSO runs the findings analyzer container (`cspr-toolkit-findings:latest`).

#### Automated Execution:
```bash
./scripts/05_generate_findings.sh
```

#### Output Deliverables:
1. **BigQuery Table:** `${BQ_PROJECT_ID}.cspr_finding.findings_summary` containing mapped CIS Google Cloud Foundations Benchmark deviations, IAM over-privileging, and architectural gaps.
2. **Exported CSV File:** `cspr_findings_${BQ_PROJECT_ID}_<TIMESTAMP>.csv` for direct import into the **CSPR Review Checklist Template**.
3. **Looker Studio Dashboard:** Connect Looker Studio to `cspr_finding` to generate interactive charts for the Week 3 Discovery Workshops.

---

## 4. Troubleshooting & FAQ

| Symptom / Error | Root Cause | Resolution |
| :--- | :--- | :--- |
| `Image not found` during `gcloud run jobs replace` | Cloud Run validates image existence in Artifact Registry upon deploy. | Run Step 1 (`02_push_scanner_image.sh`) before Step 2. |
| `PERMISSION_DENIED: run.jobs.create` | Google Cloud PSO identity lacks `roles/run.admin`. | Verify that `scripts/01_setup_cspr_prereqs.sh` bound `roles/run.admin` to reviewer account. |
| `cspr_rec` dataset is empty or has low row count | Recommender BigQuery export takes 48-72 hours. | Normal behavior. Allow 2-3 business days before running Step 4. |
| `Domain Restricted Sharing` constraint violation | Org Policy blocks external `@google.com` accounts. | Customer admin applies project-level DRS override or adds Google customer ID `C02h8e9nw` to allowed list. |
