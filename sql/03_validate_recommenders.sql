-- ==============================================================================
-- CSPR PSO Validation Query 3: Security & IAM Recommendations
-- Dataset: cspr_rec
-- ==============================================================================

-- 1. Recommendations by Category and Subtype
SELECT 
  recommender_subtype,
  category,
  state,
  COUNT(1) AS recommendations_count
FROM 
  `@PROJECT_ID@.cspr_rec.recommendations_record`
GROUP BY 
  recommender_subtype, category, state
ORDER BY 
  recommendations_count DESC;

-- 2. High-Priority IAM & Security Insights
SELECT 
  target_resource,
  description,
  severity,
  recommendation_details
FROM 
  `@PROJECT_ID@.cspr_rec.insights_record`
WHERE 
  severity IN ('CRITICAL', 'HIGH')
ORDER BY 
  last_refresh_time DESC
LIMIT 50;
