# SQL-DATAWAREHOUSE-ONE
Building a Data Warehouse with Medallion Architecture. 
# SQL Data Warehouse Project

A PostgreSQL data warehouse built with the **medallion architecture** (Bronze → Silver → Gold), integrating **CRM** and **ERP** source data into analytics-ready dimension views.

## Architecture

| Layer | Schema | Purpose | Load method |
|-------|--------|---------|-------------|
| Bronze | `bronze` | Raw copy of source CSVs, no transformation | `bronze.load_bronze()` procedure: `TRUNCATE` + `COPY` |
| Silver | `silver` | Cleaned, standardised, deduplicated data | `TRUNCATE` + `INSERT ... SELECT` from bronze |
| Gold | `gold` | Business-ready dimension views | `CREATE VIEW` over silver |

```
source_crm/cust_info_clean.csv  → bronze.crm_cust_info     → silver.crm_cust_info     ─┐
source_crm/prd_info.csv         → bronze.crm_prd_info      → silver.crm_prd_info      ─┼→ gold.dim_products
source_crm/sales_details.csv    → bronze.crm_sales_details → silver.crm_sales_details
source_erp/CUST_AZ12.csv        → bronze.erp_cust_az12     → silver.erp_cust_az12     ─┐
source_erp/LOC_A101.csv         → bronze.erp_loc_a101      → silver.erp_loc_a101      ─┼→ gold.dim_customers
source_erp/PX_CAT_G1V2.csv      → bronze.erp_px_cat_g1v2   → silver.erp_px_cat_g1v2   ─┘ (also feeds dim_products)
```

## Data Sources

| Source | Description | Files |
|--------|-------------|-------|
| CRM | Customers, products, sales transactions | `cust_info_clean.csv`, `prd_info.csv`, `sales_details.csv` |
| ERP | Customer demographics, locations, product categories | `CUST_AZ12.csv`, `LOC_A101.csv`, `PX_CAT_G1V2.csv` |

## Silver Layer: Transformations

| Table | Key transformations |
|-------|--------------------|
| `silver.crm_cust_info` | Deduplicate on `cst_id` (keep latest `cst_create_date`), trim names, decode marital status (`M`/`S`) and gender (`F`/`M`) to full words, default `N/A` |
| `silver.crm_prd_info` | Derive `cat_id` and clean `prd_key` from the raw key, replace `NULL` cost with 0, compute `prd_end_dt` as next version's start date minus 1 day |
| `silver.crm_sales_details` | Convert `YYYYMMDD` integers to dates (invalid → `NULL`), recalculate `sales` and `price` when missing, ≤ 0 or inconsistent with `quantity × price` |
| `silver.erp_cust_az12` | Strip `NAS` prefix from `cid`, null out future birth dates, normalise gender to `Female` / `Male` / `n/a` |
| `silver.erp_loc_a101` | Customer country |
| `silver.erp_px_cat_g1v2` | Straight copy of category, sub-category and maintenance flag |

All silver tables include an audit column `dwh_create_date` (load timestamp).

## Gold Layer

### `gold.dim_customers`
One row per customer, built from `crm_cust_info` joined to `erp_cust_az12` and `erp_loc_a101` on `cst_key = cid`.

| Column | Description |
|--------|-------------|
| `customer_key` | Surrogate key (`ROW_NUMBER`) |
| `customer_id` | CRM customer ID |
| `customer_number` | Business key |
| `first_name`, `last_name` | Customer name |
| `marital_status` | Marital status |
| `gender` | CRM gender, falling back to ERP gender |
| `start_date` | Customer creation date |
| `birth_date` | Birth date (ERP) |
| `country` | Country (ERP) |

### `gold.dim_products`
One row per current product (`prd_end_dt IS NULL`), built from `crm_prd_info` joined to `erp_px_cat_g1v2` on `cat_id = id`.

| Column | Description |
|--------|-------------|
| `serial` | Surrogate key (`ROW_NUMBER`) |
| `product_id`, `product_key`, `product_number` | Product ID, key and name |
| `cost_in_dollors` | Product cost |
| `line` | Product line |
| `start_date`, `end_date` | Version dates |
| `categorie_id`, `product_categorie`, `product_sub_categorie` | Category hierarchy |
| `maintenance` | Maintenance flag |

## Key Relationships

| From | To | Join |
|------|----|------|
| `crm_cust_info.cst_key` | `erp_cust_az12.cid` | Customer number |
| `crm_cust_info.cst_key` | `erp_loc_a101.cid` | Customer number |
| `crm_prd_info.cat_id` | `erp_px_cat_g1v2.id` | Category ID |
| `crm_sales_details.sls_prd_key` | `crm_prd_info.prd_key` | Product key |
| `crm_sales_details.sls_cust_id` | `crm_cust_info.cst_id` | Customer ID |

## Repository Scripts

| File | Layer | Purpose |
|------|-------|---------|
| `ddl_bronze.sql` | Bronze | `bronze.load_bronze()` load procedure |
| `ddl_silver.sql` | Silver | Silver table definitions |
| `bronze_to_silver.sql` | Silver | CRM customers transform |
| `tra_crm_prd_info.sql` | Silver | CRM products transform |
| `tra_crm_sales_details.sql` | Silver | CRM sales transform |
| `tra_erp_cust_az12.sql` | Silver | ERP customer transform |
| `tra_erp_px_cat_g1v2.sql` | Silver | ERP product category load |
| `gold_dim_cust.sql` | Gold | `gold.dim_customers` view |
| `gold_dim_products.sql` | Gold | `gold.dim_products` view |

## Roadmap

- [ ] Add `cat_id` column to `silver.crm_prd_info` DDL
- [ ] Change `silver.crm_sales_details` date columns from `INT` to `DATE`
- [ ] Fix gender fallback in `gold.dim_customers` (compare against `'N/A'`)
- [ ] Add `TRUNCATE` to `tra_crm_prd_info.sql`
- [ ] Add silver transform for `erp_loc_a101`
- [ ] Build `gold.fact_sales`
- [ ] Replace hard-coded file paths in `bronze.load_bronze()`
