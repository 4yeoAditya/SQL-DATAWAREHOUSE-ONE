TRUNCATE TABLE SILVER.erp_cust_az12;
INSERT INTO SILVER.erp_cust_az12 (
	cid,
	bdate,
	gen
)


SELECT 
	CASE WHEN cid like 'NAS%' THEN SUBSTRING(cid,4,length(cid))
		 ELSE cid
	END cid,
	CASE WHEN bdate > CURRENT_TIMESTAMP THEN NULL
		 ELSE bdate
	END bdate,
	CASE WHEN upper(trim(gen)) in ('F' , 'FEMALE') THEN 'Female'
		 WHEN upper(trim(gen)) in ('M' , 'MALE') THEN 'Male'
	 	 ELSE 'n/a'
	END gen
FROM bronze.erp_cust_az12
