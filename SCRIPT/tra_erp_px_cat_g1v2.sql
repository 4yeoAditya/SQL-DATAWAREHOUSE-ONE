TRUNCATE TABLE SILVER.erp_px_cat_g1v2;

INSERT INTO SILVER.erp_px_cat_g1v2(
	id,
	cat,
	subcat,
	maintenance
)


SELECT 
	id,
	cat,
	subcat,
	maintenance
FROM bronze.erp_px_cat_g1v2;



