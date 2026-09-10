# Cloud Security Posture Remediation (CSPR)
## Google Cloud Security Posture Review & Remediation Framework

[![Status](https://img.shields.io/badge/Status-Operational%20v3.0-success.svg)](README.md)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Security](https://img.shields.io/badge/Security-Monitored-success.svg)](SECURITY.md)
[![CI/CD](https://img.shields.io/badge/CI%2FCD-Gitleaks%20%7C%20TruffleHog%20%7C%20SAST-brightgreen.svg)](.github/workflows/)

---
**Author:** Joabson Saccomani ([@jsaccomani](https://github.com/g-jsaccomani))  
**Role:** Cloud Security Consultant / Google Cloud PSO Lead  
**LinkedIn:** [linkedin.com/in/jsaccomani](https://www.linkedin.com/in/jsaccomani)  
*Copyright © 2026 Google LLC / Joabson Saccomani. All rights reserved. Distributed under the Apache License 2.0.*

---

## Overview

**Cloud Security Posture Remediation (CSPR)** is an enterprise-grade assessment, auditing, and automated remediation framework designed for Google Cloud environments. 

It provides an end-to-end execution lifecycle to evaluate organizational cloud infrastructure against the **CIS Google Cloud Foundations Benchmark v3.0**, identify IAM over-privileging, detect cryptographic and storage vulnerabilities, and consolidate telemetry into BigQuery for automated findings generation and executive Looker Studio reporting.

---

## Architectural Lifecycle & Least-Privilege Model

All scanning operations, dataset consolidations, and security evaluations execute strictly within the **Customer's dedicated, isolated GCP audit project**. Data is never exported outside customer tenant boundaries:

```text
+---------------------------------------------------------------------------------------------------+
|                                CUSTOMER DEDICATED GCP AUDIT TENANT                                |
|                                                                                                   |
|  [Google Cloud PSO / Security Lead]                                                               |
|         │                                                                                         |
|         ├─► [1. Docker Push] ─────────► [Artifact Registry] (customer-cspr-toolkit)               |
|         │                                       │                                                 |
|         ├─► [2. Deploy & Run Job] ───► [Cloud Run Job] (cspr-prereq-job)                          |
|         │                                       │                                                 |
|         │                                (Exports Data)                                           |
|         │                                       ▼                                                 |
|         ├─► [3. BigQuery Validation] ─► [BigQuery Datasets]                                       |
|         │                                ├── cspr_cai (Immediate: Assets & IAM Allow Policies)    |
|         │                                ├── cspr_policy (Immediate: Org Policies & Keys)         |
|         │                                └── cspr_rec (48-72h: Security & IAM Recommenders)       |
|         │                                       │                                                 |
|         └─► [4. Findings Scan] ──────► [cspr_finding Dataset] ──► [Looker Studio & Review Doc]    |
+---------------------------------------------------------------------------------------------------+
```

---

## Interactive CLI Orchestrator: `pso_cspr_manager.sh`

The repository provides an interactive terminal manager that eliminates manual parameter handling, auto-detects configured projects from environment summaries, and orchestrates all phases:

```bash
./pso_cspr_manager.sh
```

### Menu Options:
1. **[Fase 01 - Setup]**: Automated provisioning of dedicated GCP Folder, project, APIs, Service Account, and Artifact Registry (`scripts/01_setup_cspr_prereqs.sh`).
2. **[Fase 02 - Push]**: Pull proprietary PSO scanner images and push them into the customer's Artifact Registry (`scripts/02_push_scanner_image.sh` or Cloud Shell `scripts/01.1_cloudshell_push_image.sh`).
3. **[Fase 03 - Deploy]**: Deploy and execute the Cloud Run Job to collect CAI, Org Policies, and Recommenders (`scripts/03_deploy_and_run_job.sh`).
4. **[Fase 04 - Validação]**: Validate BigQuery datasets, table health, and row ingestion telemetry (`scripts/04_validate_bigquery.sh`).
5. **[Fase 05 - Findings]**: Run Findings Scanner container and export findings to CSV for the CSPR Checklist / Looker Studio (`scripts/05_generate_findings.sh`).
6. **[Pipeline Completo]**: Execute Fases 02 -> 04 sequentially with a single command.
7. **[Configuração]**: Switch target GCP project, Organization ID, and region.
8. **[Relatório]**: Inspect latest environment setup summary.

---

## Repository Structure

```text
cspr/
├── .github/
│   ├── workflows/
│   │   ├── Gitleaks.yml          # Automated secret detection
│   │   ├── TruffleHog.yml        # High-entropy credential scanning
│   │   └── sast.yml              # Static Application Security Testing
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── pull_request_template.md
├── docs/
│   ├── CSPR_PSO_Execution_Runbook.md             # Complete technical runbook & architecture
│   ├── CSPR_PSO_Execution_Runbook.docx           # Executive Word runbook document
│   └── CSPR_Customer_Prerequisite_Setup_Guide.docx# Customer prerequisite onboarding guide
├── pso_cspr_manager.sh                           # Master interactive CLI orchestrator
├── scripts/
│   ├── 01_setup_cspr_prereqs.sh                  # Fase 01: Environment provisioning
│   ├── 01.1_cloudshell_push_image.sh             # Fase 01.1: Push via Cloud Shell
│   ├── 02_push_scanner_image.sh                  # Fase 02: Scanner image transfer
│   ├── 03_deploy_and_run_job.sh                  # Fase 03: Cloud Run Job execution
│   ├── 04_validate_bigquery.sh                   # Fase 04: BigQuery telemetry validation
│   └── 05_generate_findings.sh                   # Fase 05: Findings analysis & CSV export
├── sql/
│   ├── 01_validate_cai_assets.sql                # Cloud Asset Inventory queries
│   ├── 02_validate_org_policies.sql              # Organization policy validation
│   ├── 03_validate_recommenders.sql              # Security & IAM recommender checks
│   └── 04_export_findings_summary.sql            # Consolidated findings export
├── templates/
│   ├── cloudrun-job-v2.yaml                      # Base Cloud Run Job manifest
│   ├── cloudrun-prereq-job.template.yaml         # Telemetry collection job template
│   └── cloudrun-findings-job.template.yaml       # Findings scanner job template
├── local_tests/                                  # Sanitized test fixtures and sample reports
├── engine/                                       # Core evaluation engine modules
├── policies/                                     # Security posture policy definitions
├── remediation/                                  # Automated remediation playbooks
├── .gitignore
├── CHANGELOG.md
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── LICENSE
├── README.md
└── SECURITY.md
```

---

## BigQuery Telemetry Ingestion Timing

| Dataset | Telemetry Domain | Ingestion Window | Description |
| :--- | :--- | :---: | :--- |
| `cspr_cai` | Cloud Asset Inventory | Immediate (0 - 2h) | Asset topology, compute, storage, firewalls, and IAM bindings. |
| `cspr_policy` | Policy Analyzer & Keys | Immediate (0 - 2h) | Organization Policy constraints and Service Account key age/activity. |
| `cspr_rec` | Recommenders & Insights | 48 - 72h | Google Cloud Recommenders (SCC, IAM over-granting, idle resources). |
| `cspr_finding` | Scanner Output | Post-Ingestion | Mapped CIS benchmark deviations, severity ratings, and remediation guidance. |

---

## Security & Secret Scanning

This repository is guarded by continuous CI/CD security workflows:
- **Gitleaks**: Scans every commit and pull request for exposed API keys, private tokens, and credentials.
- **TruffleHog**: Analyzes git history and commit payloads for high-entropy secrets and verified tokens.
- **SAST**: Automated static code security inspection.

Please review our [SECURITY.md](SECURITY.md) for vulnerability disclosure policies.

---

## Getting Started

### Prerequisites
- [Google Cloud SDK (`gcloud`)](https://cloud.google.com/sdk/docs/install) (>= 450.0.0)
- [Docker](https://docs.docker.com/get-docker/) or Google Cloud Shell
- Access to target customer project with `roles/owner` or `roles/resourcemanager.organizationAdmin`

### Clone & Execution
```bash
git clone git@github.com:g-jsaccomani/cspr.git
cd cspr
chmod +x pso_cspr_manager.sh scripts/*.sh
./pso_cspr_manager.sh
```

---

## License

This project is licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
