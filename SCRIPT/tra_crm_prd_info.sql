INSERT INTO silver.crm_prd_info
(
	prd_id,
	prd_nm,
	cat_id,
	prd_key,
	prd_cost,
	prd_line,
	prd_start_dt,
	prd_end_dt
)
SELECT
	prd_id,
	prd_nm,
	REPLACE(SUBSTRING(prd_key, 1, 5), '-', '_') AS cat_id,
	SUBSTRING(prd_key, 7, LENGTH(prd_key)) AS prd_key,
	COALESCE(prd_cost, 0) AS prd_cost,
	prd_line,
	CAST(prd_start_dt AS DATE) AS prd_start_dt,
	LEAD(CAST(prd_start_dt AS DATE)) OVER (
		PARTITION BY prd_key
		ORDER BY prd_start_dt
	) - 1 AS prd_end_dt
FROM bronze.crm_prd_info;