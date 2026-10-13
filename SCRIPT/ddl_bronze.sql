CREATE OR REPLACE PROCEDURE bronze.load_bronze()
AS $$
BEGIN
	RAISE NOTICE 'Printing the bronze layer.';
	RAISE NOTICE 'Loading CRM';
	TRUNCATE table  bronze.crm_cust_info;
	COPY  bronze.crm_cust_info
	FROM '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_crm/cust_info_clean.csv'
	WITH (
	    FORMAT CSV,
	    HEADER TRUE,
	    DELIMITER ','
	);
	TRUNCATE table  bronze.crm_prd_info;
	COPY bronze.crm_prd_info
	FROM '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_crm/prd_info.csv'
	WITH (
	    FORMAT CSV,
	    HEADER TRUE,
	    DELIMITER ','
	);
	TRUNCATE table  bronze.crm_sales_details;
	COPY bronze.crm_sales_details
	FROM '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_crm/sales_details.csv'
	WITH (
	    FORMAT CSV,
	    HEADER TRUE,
	    DELIMITER ','
	);
	RAISE NOTICE 'Loading CRM'
	TRUNCATE table bronze.erp_cust_az12;
	COPY bronze.erp_cust_az12
	FROM '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_erp/CUST_AZ12.csv'
	WITH (
	    FORMAT CSV,
	    HEADER TRUE,
	    DELIMITER ','
	);
	TRUNCATE table bronze.erp_loc_a101;
	copy bronze.erp_loc_a101
	from '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_erp/LOC_A101.csv'
	with(
		format csv,
		header true,
		delimiter ','
	);
	TRUNCATE table bronze.erp_px_cat_g1v2;
	copy bronze.erp_px_cat_g1v2
	from '/Users/adityaraj/Desktop/sql-data-warehouse-project/datasets/source_erp/PX_CAT_G1V2.csv'
	with(
		format csv,
		header true,
		delimiter ','
	);
	
END;
$$ LANGUAGE plpgsql;

