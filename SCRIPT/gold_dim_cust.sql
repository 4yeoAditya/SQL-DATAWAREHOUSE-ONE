-- dimension of customer table 
-- use surrogate key

CREATE VIEW gold.dim_customers AS
SELECT 
	ROW_NUMBER() OVER(ORDER BY CST_ID) AS customer_key,
	ci.cst_id as customer_id,
	ci.cst_key as customer_number,
	ci.cst_firstname as first_name,
	ci.cst_lastname as last_name,
	ci.cst_marital_status as marital_status,
	CASE WHEN ci.cst_gndr !='n/a' THEN ci.cst_gndr
		 ELSE COALESCE(ca.gen, 'n/a')
	END as gender,
	ci.cst_create_date as Start_date,
	ca.bdate as Birth_date,
	la.cntry as country
FROM silver.crm_cust_info ci
LEFT JOIN silver.erp_cust_az12 ca
ON ci.cst_key = ca.cid
LEFT JOIN silver.erp_loc_a101 la
on ci.cst_key=la.cid