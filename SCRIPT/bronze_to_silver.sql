INSERT INTO silver.crm_cust_info(
	cst_id,
	cst_key,
	cst_firstname,
	cst_lastname,
	cst_marital_status,
	cst_gndr,
	cst_create_date
)
-- removal of dublicates and fixing of names and changing data to full forms 
WITH cte AS(
	SELECT 
	*,
	ROW_NUMBER() OVER(PARTITION BY cst_id order by cst_create_date desc) as flag
	FROM bronze.crm_cust_info
)
SELECT
    cst_id,
    cst_key,
    TRIM(cst_firstname) AS cst_firstname,
    TRIM(cst_lastname) AS cst_lastname,
    CASE
        WHEN TRIM(UPPER(cst_marital_status)) = 'M' THEN 'MARRIED'
        WHEN TRIM(UPPER(cst_marital_status)) = 'S' THEN 'SINGLE'
        ELSE 'N/A'
    END AS cst_marital_status,
    CASE
        WHEN TRIM(UPPER(cst_gndr)) = 'F' THEN 'FEMALE'
        WHEN TRIM(UPPER(cst_gndr)) = 'M' THEN 'MALE'
        ELSE 'N/A'
    END AS cst_gndr,
    cst_create_date
FROM cte
WHERE flag = 1;





