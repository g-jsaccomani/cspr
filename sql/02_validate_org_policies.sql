-- ==============================================================================
-- CSPR PSO Validation Query 2: Organization Policies & Policy Analyzer
-- Dataset: cspr_policy
-- ==============================================================================

-- 1. Organization Policies Summary
SELECT 
  constraint,
  COUNT(1) AS evaluated_resources,
  COUNT(DISTINCT project_id) AS distinct_projects
FROM 
  `@PROJECT_ID@.cspr_policy.orgpolicy_cache`
GROUP BY 
  constraint
ORDER BY 
  evaluated_resources DESC;

-- 2. Service Account Activity Analysis (Unused Keys / Inactive Principals)
SELECT 
  service_account_email,
  key_id,
  last_authenticated_time,
  is_active
FROM 
  `@PROJECT_ID@.cspr_policy.service_account_keys`
WHERE 
  last_authenticated_time < TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 90 DAY)
  OR last_authenticated_time IS NULL
ORDER BY 
  last_authenticated_time ASC;
