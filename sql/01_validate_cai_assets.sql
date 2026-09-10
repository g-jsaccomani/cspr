-- ==============================================================================
-- CSPR PSO Validation Query 1: Cloud Asset Inventory (CAI) Assets & IAM
-- Dataset: cspr_cai
-- ==============================================================================

-- 1. Total Discovered Resources by Asset Type
SELECT 
  asset_type,
  COUNT(1) AS total_resources,
  COUNT(DISTINCT project_id) AS distinct_projects_count
FROM 
  `@PROJECT_ID@.cspr_cai.resource_cache`
GROUP BY 
  asset_type
ORDER BY 
  total_resources DESC
LIMIT 50;

-- 2. Projects Ingestion Summary
SELECT 
  project_id,
  COUNT(1) AS total_assets,
  MIN(update_time) AS earliest_asset_time,
  MAX(update_time) AS latest_asset_time
FROM 
  `@PROJECT_ID@.cspr_cai.resource_cache`
GROUP BY 
  project_id
ORDER BY 
  total_assets DESC;

-- 3. IAM Policy Cache Validation
SELECT 
  resource,
  COUNT(1) AS binding_count
FROM 
  `@PROJECT_ID@.cspr_cai.iam_policy_cache`
GROUP BY 
  resource
LIMIT 20;
