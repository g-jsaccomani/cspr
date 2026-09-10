-- ==============================================================================
-- CSPR PSO Validation Query 4: Consolidated Findings Summary (CSPR Scanner)
-- Dataset: cspr_finding
-- ==============================================================================

-- 1. Findings Distribution by Severity
SELECT 
  severity,
  COUNT(1) AS total_findings,
  COUNT(DISTINCT target_resource) AS affected_resources_count,
  COUNT(DISTINCT project_id) AS affected_projects_count
FROM 
  `@PROJECT_ID@.cspr_finding.findings_summary`
GROUP BY 
  severity
ORDER BY 
  CASE severity 
    WHEN 'CRITICAL' THEN 1 
    WHEN 'HIGH' THEN 2 
    WHEN 'MEDIUM' THEN 3 
    WHEN 'LOW' THEN 4 
    ELSE 5 
  END;

-- 2. Top Security Findings by CIS Benchmark / Rule ID
SELECT 
  rule_id,
  rule_name,
  severity,
  category,
  COUNT(1) AS violation_count
FROM 
  `@PROJECT_ID@.cspr_finding.findings_summary`
GROUP BY 
  rule_id, rule_name, severity, category
ORDER BY 
  violation_count DESC
LIMIT 30;

-- 3. Detailed Non-Compliant Resources Export (for Review Checklist & Looker)
SELECT 
  project_id,
  target_resource,
  rule_id,
  rule_name,
  severity,
  description,
  remediation_recommendation
FROM 
  `@PROJECT_ID@.cspr_finding.findings_summary`
ORDER BY 
  severity DESC, project_id ASC;
