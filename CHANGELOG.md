# Changelog - cspr

All notable changes and security updates recorded below.

### [2025-11-20] feat(engine): scaffold core Cloud Security Posture Remediation engine architecture
- Completed milestone deliverables and technical verification.

### [2025-12-16] feat(policies): define CIS Google Cloud Benchmark security audit policies
- Completed milestone deliverables and technical verification.

### [2026-01-13] sec(remediation): implement automated remediation playbooks for cloud misconfigurations
- Completed milestone deliverables and technical verification.

### [2026-02-10] feat(scripts): add CLI assessment and batch execution utility scripts
- Completed milestone deliverables and technical verification.

### [2026-03-10] docs(architecture): document CSPR scoring methodology and remediation workflows
- Completed milestone deliverables and technical verification.

### [2026-05-05] ci(workflows): configure automated SAST security scanning and GitHub issue templates
- Completed milestone deliverables and technical verification.

### [2026-08-21] chore(release): verify production artifacts and security integrity
- Finalized and audited all codebase schemas, security configurations, and benchmark baselines.

### [2026-09-10] feat(toolkit): merge Google Cloud PSO CSPR execution suite with full client sanitization
- Merged master CLI orchestrator (`pso_cspr_manager.sh`) covering all execution phases (01 to 05).
- Integrated phased automation scripts (`01_setup_cspr_prereqs.sh`, `01.1_cloudshell_push_image.sh`, `02_push_scanner_image.sh`, `03_deploy_and_run_job.sh`, `04_validate_bigquery.sh`, `05_generate_findings.sh`).
- Integrated Cloud Run Job manifest templates and BigQuery CIS validation queries (`sql/`).
- Migrated sanitized technical documentation (`CSPR_PSO_Execution_Runbook.md`, `.docx`, customer guides).
- Removed redundant Step 3 files and consolidated operational guidance into `CSPR_PSO_Execution_Runbook`.
- Enforced complete customer sanitization across all codebase scripts, templates, test summaries, and manifests.
- Harmonized security pipelines (Gitleaks, TruffleHog, SAST) and GitHub governance standards across both repositories.

