CREATE VIEW gold.dim_products AS
SELECT 
	ROW_NUMBER() OVER(order by prd_id) as serial,
	prd_id as Product_ID,
	prd_key as Product_KEY,
	prd_nm as Product_Number,
	prd_cost as Cost_In_Dollors,
	prd_line as Line,
	prd_start_dt as Start_Date,
	prd_end_dt End_Date,
	cat_id as Categorie_id,
	pc.cat as Product_categorie,
	pc.subcat as Product_sub_categorie,
	pc.maintenance as Maintenance
FROM silver.crm_prd_info pn
LEFT JOIN silver.erp_px_cat_g1v2 pc
ON pn.cat_id = pc.id
WHERE prd_end_dt is null;
