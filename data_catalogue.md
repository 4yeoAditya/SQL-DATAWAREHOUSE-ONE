# Data Catalogue: SQL Data Warehouse

A PostgreSQL data warehouse built with a **medallion architecture** (Bronze → Silver → Gold) from two source systems, **CRM** and **ERP**.

## 1. Architecture Overview

| Layer | Schema | Purpose | Load method |
|-------|--------|---------|-------------|
| Bronze | `bronze` | Raw copy of source CSVs, no transformation | `bronze.load_bronze()` procedure: `TRUNCATE` + `COPY` |
| Silver | `silver` | Cleaned, standardised, deduplicated data | `TRUNCATE` + `INSERT ... SELECT` from bronze |
| Gold | `gold` | Business-ready dimension views | `CREATE VIEW` over silver |

### Data flow

```
source_crm/cust_info_clean.csv  → bronze.crm_cust_info     → silver.crm_cust_info     ─┐
source_crm/prd_info.csv         → bronze.crm_prd_info      → silver.crm_prd_info      ─┼→ gold.dim_products
source_crm/sales_details.csv    → bronze.crm_sales_details → silver.crm_sales_details    (no gold fact view yet)
source_erp/CUST_AZ12.csv        → bronze.erp_cust_az12     → silver.erp_cust_az12     ─┐
source_erp/LOC_A101.csv         → bronze.erp_loc_a101      → silver.erp_loc_a101      ─┼→ gold.dim_customers
source_erp/PX_CAT_G1V2.csv      → bronze.erp_px_cat_g1v2   → silver.erp_px_cat_g1v2   ─┘ (also feeds dim_products)
```

### Source systems

| Source | Description | Files |
|--------|-------------|-------|
| CRM | Customer, product and sales transaction data | `cust_info_clean.csv`, `prd_info.csv`, `sales_details.csv` |
| ERP | Customer demographics, locations, product categories | `CUST_AZ12.csv`, `LOC_A101.csv`, `PX_CAT_G1V2.csv` |

---

## 2. Bronze Layer

Loaded by `bronze.load_bronze()` (file: `ddl_bronze.sql`). Each table is truncated and fully reloaded with `COPY ... WITH (FORMAT CSV, HEADER TRUE, DELIMITER ',')`.

| Table | Source file | Notes |
|-------|-------------|-------|
| `bronze.crm_cust_info` | `source_crm/cust_info_clean.csv` | Raw customers; may contain duplicate `cst_id` rows |
| `bronze.crm_prd_info` | `source_crm/prd_info.csv` | Raw product history; `prd_key` combines category and product key |
| `bronze.crm_sales_details` | `source_crm/sales_details.csv` | Raw sales lines; dates stored as integers (`YYYYMMDD`) |
| `bronze.erp_cust_az12` | `source_erp/CUST_AZ12.csv` | Raw customer birth date and gender |
| `bronze.erp_loc_a101` | `source_erp/LOC_A101.csv` | Raw customer country |
| `bronze.erp_px_cat_g1v2` | `source_erp/PX_CAT_G1V2.csv` | Raw product category reference |

> The `CREATE TABLE` statements for bronze are not in the uploaded scripts, so bronze column types are not documented here. Columns are the same as the silver tables below, minus `dwh_create_date` and the derived `cat_id`.

---

## 3. Silver Layer

Every silver table has an audit column `dwh_create_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP`.

### 3.1 `silver.crm_cust_info`
**Grain:** one row per customer (`cst_id`). **Source:** `bronze.crm_cust_info`. **Script:** `bronze_to_silver.sql`

| Column | Type | Description |
|--------|------|-------------|
| `cst_id` | INT | Customer ID from CRM |
| `cst_key` | VARCHAR(50) | Customer number; join key to ERP tables |
| `cst_firstname` | VARCHAR(50) | First name (trimmed) |
| `cst_lastname` | VARCHAR(50) | Last name (trimmed) |
| `cst_marital_status` | VARCHAR(15) | `MARRIED`, `SINGLE` or `N/A` |
| `cst_gndr` | VARCHAR(15) | `FEMALE`, `MALE` or `N/A` |
| `cst_create_date` | DATE | Date the customer record was created |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

**Transformations**
- Deduplicate on `cst_id`: `ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC)`, keep latest (`flag = 1`).
- Trim first and last names.
- Decode marital status: `M` → `MARRIED`, `S` → `SINGLE`, otherwise `N/A`.
- Decode gender: `F` → `FEMALE`, `M` → `MALE`, otherwise `N/A`.

### 3.2 `silver.crm_prd_info`
**Grain:** one row per product version (start date). **Source:** `bronze.crm_prd_info`. **Script:** `tra_crm_prd_info.sql`

| Column | Type | Description |
|--------|------|-------------|
| `prd_id` | INT | Product ID |
| `cat_id` | VARCHAR | Category ID derived from `prd_key`; join key to `erp_px_cat_g1v2.id` (**see Known Issues**) |
| `prd_key` | VARCHAR(100) | Product key (category prefix removed); join key to sales |
| `prd_nm` | VARCHAR(150) | Product name |
| `prd_cost` | INT | Product cost (`NULL` replaced with 0) |
| `prd_line` | VARCHAR(5) | Product line code |
| `prd_start_dt` | DATE | Version start date |
| `prd_end_dt` | DATE | Version end date; `NULL` for the current version |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

**Transformations**
- `cat_id` = first 5 characters of `prd_key` with `-` replaced by `_`.
- `prd_key` = remainder of the key from character 7 onward.
- `prd_cost` = `COALESCE(prd_cost, 0)`.
- `prd_end_dt` = next version's start date minus 1 day (`LEAD` over the product key ordered by start date), giving slowly-changing-dimension style history.

### 3.3 `silver.crm_sales_details`
**Grain:** one row per order line. **Source:** `bronze.crm_sales_details`. **Script:** `tra_crm_sales_details.sql`

| Column | Type | Description |
|--------|------|-------------|
| `sls_ord_num` | VARCHAR(50) | Sales order number |
| `sls_prd_key` | VARCHAR(100) | Product key (links to `crm_prd_info.prd_key`) |
| `sls_cust_id` | INT | Customer ID (links to `crm_cust_info.cst_id`) |
| `sls_order_dt` | INT* | Order date |
| `sls_ship_dt` | INT* | Shipping date |
| `sls_due_dt` | INT* | Due date |
| `sls_sales` | INT | Total sales amount |
| `sls_quantity` | INT | Units sold |
| `sls_price` | INT | Unit price |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

\* The transform produces `DATE` values; see Known Issues.

**Transformations**
- Dates: converted from `YYYYMMDD` integer with `TO_DATE`; `NULL` if the value is 0 or not 8 digits.
- `sls_sales`: recalculated as `quantity × ABS(price)` when it is `NULL`, ≤ 0, or does not equal `quantity × ABS(price)`.
- `sls_price`: derived as `sales ÷ NULLIF(quantity, 0)` when `NULL` or ≤ 0.

### 3.4 `silver.erp_cust_az12`
**Grain:** one row per customer. **Source:** `bronze.erp_cust_az12`. **Script:** `tra_erp_cust_az12.sql`

| Column | Type | Description |
|--------|------|-------------|
| `cid` | VARCHAR(100) | Customer ID; matches `crm_cust_info.cst_key` |
| `bdate` | DATE | Birth date |
| `gen` | VARCHAR(15) | `Female`, `Male` or `n/a` |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

**Transformations**
- Remove the `NAS` prefix from `cid`.
- Set future birth dates to `NULL`.
- Normalise gender: `F`/`FEMALE` → `Female`, `M`/`MALE` → `Male`, otherwise `n/a`.

### 3.5 `silver.erp_loc_a101`
**Grain:** one row per customer. **Source:** `bronze.erp_loc_a101`. **Script:** not included in uploaded files.

| Column | Type | Description |
|--------|------|-------------|
| `cid` | VARCHAR(100) | Customer ID; joins to `crm_cust_info.cst_key` |
| `cntry` | VARCHAR(50) | Country |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

### 3.6 `silver.erp_px_cat_g1v2`
**Grain:** one row per product category. **Source:** `bronze.erp_px_cat_g1v2`. **Script:** `tra_erp_px_cat_g1v2.sql`

| Column | Type | Description |
|--------|------|-------------|
| `id` | VARCHAR(7) | Category ID; joins to `crm_prd_info.cat_id` |
| `cat` | VARCHAR(30) | Category |
| `subcat` | VARCHAR(50) | Sub-category |
| `maintenance` | VARCHAR(10) | Maintenance flag |
| `dwh_create_date` | TIMESTAMP | Warehouse load timestamp |

**Transformations:** straight copy (truncate and reload), no cleansing.

---

## 4. Gold Layer

### 4.1 `gold.dim_customers` (view)
**Grain:** one row per customer. **Script:** `gold_dim_cust.sql`
**Sources:** `silver.crm_cust_info` LEFT JOIN `silver.erp_cust_az12` (on `cst_key = cid`) LEFT JOIN `silver.erp_loc_a101` (on `cst_key = cid`)

| Column | Source | Description |
|--------|--------|-------------|
| `customer_key` | `ROW_NUMBER() OVER (ORDER BY cst_id)` | Surrogate key |
| `customer_id` | `crm_cust_info.cst_id` | CRM customer ID |
| `customer_number` | `crm_cust_info.cst_key` | Business key |
| `first_name` | `crm_cust_info.cst_firstname` | First name |
| `last_name` | `crm_cust_info.cst_lastname` | Last name |
| `marital_status` | `crm_cust_info.cst_marital_status` | Marital status |
| `gender` | CRM gender, falling back to ERP `gen` | Gender (CRM is the master source) |
| `start_date` | `crm_cust_info.cst_create_date` | Customer creation date |
| `birth_date` | `erp_cust_az12.bdate` | Birth date |
| `country` | `erp_loc_a101.cntry` | Country |

### 4.2 `gold.dim_products` (view)
**Grain:** one row per current product. **Script:** `gold_dim_products.sql`
**Sources:** `silver.crm_prd_info` LEFT JOIN `silver.erp_px_cat_g1v2` (on `cat_id = id`)
**Filter:** `prd_end_dt IS NULL` (current versions only, so history is excluded)

| Column | Source | Description |
|--------|--------|-------------|
| `serial` | `ROW_NUMBER() OVER (ORDER BY prd_id)` | Surrogate key |
| `product_id` | `prd_id` | Product ID |
| `product_key` | `prd_key` | Product key |
| `product_number` | `prd_nm` | Product name |
| `cost_in_dollors` | `prd_cost` | Product cost |
| `line` | `prd_line` | Product line |
| `start_date` | `prd_start_dt` | Version start date |
| `end_date` | `prd_end_dt` | Always `NULL` due to the filter |
| `categorie_id` | `cat_id` | Category ID |
| `product_categorie` | `erp_px_cat_g1v2.cat` | Category |
| `product_sub_categorie` | `erp_px_cat_g1v2.subcat` | Sub-category |
| `maintenance` | `erp_px_cat_g1v2.maintenance` | Maintenance flag |

---

## 5. Key Relationships

| From | To | Join |
|------|----|------|
| `crm_cust_info.cst_key` | `erp_cust_az12.cid` | Customer number |
| `crm_cust_info.cst_key` | `erp_loc_a101.cid` | Customer number |
| `crm_prd_info.cat_id` | `erp_px_cat_g1v2.id` | Category ID |
| `crm_sales_details.sls_prd_key` | `crm_prd_info.prd_key` | Product key |
| `crm_sales_details.sls_cust_id` | `crm_cust_info.cst_id` | Customer ID |

---

## 6. Known Issues and Suggested Fixes

Found while documenting the scripts:

1. **`silver.crm_prd_info` DDL has no `cat_id` column.** The transform inserts into it and `gold.dim_products` reads it. Add `cat_id VARCHAR(50)` to the DDL.
2. **`silver.crm_sales_details` date columns are `INT`, but the transform outputs `DATE`.** The insert will fail. Change `sls_order_dt`, `sls_ship_dt` and `sls_due_dt` to `DATE`.
3. **Gender fallback in `gold.dim_customers` never triggers.** Silver stores `'N/A'` (uppercase) but the view tests `!= 'n/a'`, so ERP gender is never used. Compare against `'N/A'`. Casing also differs between CRM (`FEMALE`) and ERP (`Female`); standardise one.
4. **Syntax error in `bronze.load_bronze()`.** `RAISE NOTICE 'Loading CRM'` before the ERP section is missing a semicolon (and should likely say `Loading ERP`).
5. **`tra_crm_prd_info.sql` has no `TRUNCATE`.** Re-running it duplicates rows, unlike the other transform scripts.
6. **No silver transform script for `erp_loc_a101`.** Gold depends on it; country values are probably worth cleansing (e.g. codes like `DE`/`US`).
7. **`gold.dim_products` drops product history** (`prd_end_dt IS NULL`), so `end_date` is always `NULL`. If sales should map to the product version active at order time, keep history and join on dates.
8. **No gold fact view yet** for `silver.crm_sales_details`; a `gold.fact_sales` view joining to both dimensions would complete the star schema.
9. **Naming typos in gold:** `cost_in_dollors`, `categorie_id`, `product_categorie`, `product_sub_categorie`. Fix before downstream use, as renaming later breaks queries.
10. **Hard-coded absolute file paths** in the bronze procedure (`/Users/.../datasets/...`) make it non-portable.

---

## 7. Script Inventory

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
