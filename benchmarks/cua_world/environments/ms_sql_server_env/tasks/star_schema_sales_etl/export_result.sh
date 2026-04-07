#!/bin/bash
# Export results for star_schema_sales_etl task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# Read reference values
REF_LINETOTAL=$(grep "Reference_LineTotal:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_TAX=$(grep "Reference_Tax:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_FREIGHT=$(grep "Reference_Freight:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_PRODUCTS=$(grep "Product_Count:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_CUSTOMERS=$(grep "Customer_Count:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_LINEITEMS=$(grep "LineItem_Count:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_NULL_SUBCAT=$(grep "NULL_Subcategory_Products:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
REF_STORE_ONLY=$(grep "Store_Only_Customers:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')

DB="AdventureWorks2022"

# ── Check: DW schema exists ───────────────────────────────────────────────────
SCHEMA_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    SC=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'DW'" "$DB" | tr -d ' \r\n')
    [ "${SC:-0}" -gt 0 ] 2>/dev/null && SCHEMA_EXISTS="true"
fi

# ── Check: DW.DimDate ─────────────────────────────────────────────────────────
DIMDATE_EXISTS="false"
DIMDATE_ROWS=0
DIMDATE_COLS=0
DIMDATE_FY_TEST=0
DIMDATE_FQ_TEST=0
DIMDATE_WEEKEND=-1

if [ "$MSSQL_RUNNING" = "true" ]; then
    DC=$(mssql_query "SELECT CASE WHEN OBJECT_ID('DW.DimDate','U') IS NOT NULL THEN 1 ELSE 0 END" "$DB" | tr -d ' \r\n')
    [ "${DC:-0}" -gt 0 ] 2>/dev/null && DIMDATE_EXISTS="true"

    if [ "$DIMDATE_EXISTS" = "true" ]; then
        DIMDATE_ROWS=$(mssql_query "SELECT COUNT(*) FROM DW.DimDate" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMDATE_ROWS=${DIMDATE_ROWS:-0}

        DIMDATE_COLS=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DW' AND TABLE_NAME='DimDate'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMDATE_COLS=${DIMDATE_COLS:-0}

        DIMDATE_FY_TEST=$(mssql_query "SELECT ISNULL(FiscalYear, 0) FROM DW.DimDate WHERE FullDate = '2013-07-15'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMDATE_FY_TEST=${DIMDATE_FY_TEST:-0}

        DIMDATE_FQ_TEST=$(mssql_query "SELECT ISNULL(FiscalQuarter, 0) FROM DW.DimDate WHERE FullDate = '2013-10-15'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMDATE_FQ_TEST=${DIMDATE_FQ_TEST:-0}

        DIMDATE_WEEKEND=$(mssql_query "SELECT CAST(ISNULL(IsWeekend, 0) AS INT) FROM DW.DimDate WHERE FullDate = '2013-01-05'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMDATE_WEEKEND=${DIMDATE_WEEKEND:--1}
    fi
fi

# ── Check: DW.DimProduct ──────────────────────────────────────────────────────
DIMPROD_EXISTS="false"
DIMPROD_ROWS=0
DIMPROD_HAS_SK="false"
DIMPROD_UNCAT=0
DIMPROD_GENERAL=0

if [ "$MSSQL_RUNNING" = "true" ]; then
    PC=$(mssql_query "SELECT CASE WHEN OBJECT_ID('DW.DimProduct','U') IS NOT NULL THEN 1 ELSE 0 END" "$DB" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] 2>/dev/null && DIMPROD_EXISTS="true"

    if [ "$DIMPROD_EXISTS" = "true" ]; then
        DIMPROD_ROWS=$(mssql_query "SELECT COUNT(*) FROM DW.DimProduct" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMPROD_ROWS=${DIMPROD_ROWS:-0}

        SKC=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DW' AND TABLE_NAME='DimProduct' AND COLUMN_NAME='ProductSK'" "$DB" 2>/dev/null | tr -d ' \r\n')
        [ "${SKC:-0}" -gt 0 ] 2>/dev/null && DIMPROD_HAS_SK="true"

        DIMPROD_UNCAT=$(mssql_query "SELECT COUNT(*) FROM DW.DimProduct WHERE CategoryName = 'Uncategorized'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMPROD_UNCAT=${DIMPROD_UNCAT:-0}

        DIMPROD_GENERAL=$(mssql_query "SELECT COUNT(*) FROM DW.DimProduct WHERE SubcategoryName = 'General'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMPROD_GENERAL=${DIMPROD_GENERAL:-0}
    fi
fi

# ── Check: DW.DimCustomer ─────────────────────────────────────────────────────
DIMCUST_EXISTS="false"
DIMCUST_ROWS=0
DIMCUST_HAS_SK="false"
DIMCUST_STORES=0
DIMCUST_INDIVIDUALS=0
DIMCUST_STORE_PREFIX=0

if [ "$MSSQL_RUNNING" = "true" ]; then
    CC=$(mssql_query "SELECT CASE WHEN OBJECT_ID('DW.DimCustomer','U') IS NOT NULL THEN 1 ELSE 0 END" "$DB" | tr -d ' \r\n')
    [ "${CC:-0}" -gt 0 ] 2>/dev/null && DIMCUST_EXISTS="true"

    if [ "$DIMCUST_EXISTS" = "true" ]; then
        DIMCUST_ROWS=$(mssql_query "SELECT COUNT(*) FROM DW.DimCustomer" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMCUST_ROWS=${DIMCUST_ROWS:-0}

        SKC=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DW' AND TABLE_NAME='DimCustomer' AND COLUMN_NAME='CustomerSK'" "$DB" 2>/dev/null | tr -d ' \r\n')
        [ "${SKC:-0}" -gt 0 ] 2>/dev/null && DIMCUST_HAS_SK="true"

        DIMCUST_STORES=$(mssql_query "SELECT COUNT(*) FROM DW.DimCustomer WHERE CustomerType = 'Store'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMCUST_STORES=${DIMCUST_STORES:-0}

        DIMCUST_INDIVIDUALS=$(mssql_query "SELECT COUNT(*) FROM DW.DimCustomer WHERE CustomerType = 'Individual'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMCUST_INDIVIDUALS=${DIMCUST_INDIVIDUALS:-0}

        DIMCUST_STORE_PREFIX=$(mssql_query "SELECT COUNT(*) FROM DW.DimCustomer WHERE CustomerName LIKE 'Store:%'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        DIMCUST_STORE_PREFIX=${DIMCUST_STORE_PREFIX:-0}
    fi
fi

# ── Check: DW.FactSales ──────────────────────────────────────────────────────
FACT_EXISTS="false"
FACT_ROWS=0
FACT_COLS=0
FACT_LINETOTAL="0.00"
LINETOTAL_DIFF="999999.99"
FACT_TAX="0.00"
TAX_DIFF="999999.99"
FACT_FREIGHT="0.00"
FREIGHT_DIFF="999999.99"
ORPHAN_PROD=-1
ORPHAN_CUST=-1
ORPHAN_ODATE=-1
ORPHAN_SDATE=-1

if [ "$MSSQL_RUNNING" = "true" ]; then
    FC=$(mssql_query "SELECT CASE WHEN OBJECT_ID('DW.FactSales','U') IS NOT NULL THEN 1 ELSE 0 END" "$DB" | tr -d ' \r\n')
    [ "${FC:-0}" -gt 0 ] 2>/dev/null && FACT_EXISTS="true"

    if [ "$FACT_EXISTS" = "true" ]; then
        FACT_ROWS=$(mssql_query "SELECT COUNT(*) FROM DW.FactSales" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        FACT_ROWS=${FACT_ROWS:-0}

        FACT_COLS=$(mssql_query "SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='DW' AND TABLE_NAME='FactSales'" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        FACT_COLS=${FACT_COLS:-0}

        # Revenue reconciliation
        FACT_LINETOTAL=$(mssql_query "SELECT CAST(ISNULL(SUM(LineTotal),0) AS DECIMAL(18,2)) FROM DW.FactSales" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        FACT_LINETOTAL=${FACT_LINETOTAL:-0.00}

        if [ -n "$REF_LINETOTAL" ] && [ "$REF_LINETOTAL" != "0" ]; then
            LINETOTAL_DIFF=$(mssql_query "SELECT ABS(CAST('$FACT_LINETOTAL' AS DECIMAL(18,2)) - CAST('$REF_LINETOTAL' AS DECIMAL(18,2)))" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
            LINETOTAL_DIFF=${LINETOTAL_DIFF:-999999.99}
        fi

        # Tax/freight allocation reconciliation
        FACT_TAX=$(mssql_query "SELECT CAST(ISNULL(SUM(AllocatedTax),0) AS DECIMAL(18,2)) FROM DW.FactSales" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        FACT_TAX=${FACT_TAX:-0.00}

        if [ -n "$REF_TAX" ] && [ "$REF_TAX" != "0" ]; then
            TAX_DIFF=$(mssql_query "SELECT ABS(CAST('$FACT_TAX' AS DECIMAL(18,2)) - CAST('$REF_TAX' AS DECIMAL(18,2)))" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
            TAX_DIFF=${TAX_DIFF:-999999.99}
        fi

        FACT_FREIGHT=$(mssql_query "SELECT CAST(ISNULL(SUM(AllocatedFreight),0) AS DECIMAL(18,2)) FROM DW.FactSales" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        FACT_FREIGHT=${FACT_FREIGHT:-0.00}

        if [ -n "$REF_FREIGHT" ] && [ "$REF_FREIGHT" != "0" ]; then
            FREIGHT_DIFF=$(mssql_query "SELECT ABS(CAST('$FACT_FREIGHT' AS DECIMAL(18,2)) - CAST('$REF_FREIGHT' AS DECIMAL(18,2)))" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
            FREIGHT_DIFF=${FREIGHT_DIFF:-999999.99}
        fi

        # Orphaned surrogate key checks
        ORPHAN_PROD=$(mssql_query "SELECT COUNT(*) FROM DW.FactSales f WHERE NOT EXISTS (SELECT 1 FROM DW.DimProduct d WHERE d.ProductSK = f.ProductSK)" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        ORPHAN_PROD=${ORPHAN_PROD:--1}

        ORPHAN_CUST=$(mssql_query "SELECT COUNT(*) FROM DW.FactSales f WHERE NOT EXISTS (SELECT 1 FROM DW.DimCustomer d WHERE d.CustomerSK = f.CustomerSK)" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        ORPHAN_CUST=${ORPHAN_CUST:--1}

        ORPHAN_ODATE=$(mssql_query "SELECT COUNT(*) FROM DW.FactSales f WHERE NOT EXISTS (SELECT 1 FROM DW.DimDate d WHERE d.DateKey = f.OrderDateKey)" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        ORPHAN_ODATE=${ORPHAN_ODATE:--1}

        ORPHAN_SDATE=$(mssql_query "SELECT COUNT(*) FROM DW.FactSales f WHERE f.ShipDateKey IS NOT NULL AND NOT EXISTS (SELECT 1 FROM DW.DimDate d WHERE d.DateKey = f.ShipDateKey)" "$DB" 2>/dev/null | tr -d ' \r\n'; true)
        ORPHAN_SDATE=${ORPHAN_SDATE:--1}
    fi
fi

# ── Check: Stored procedure ───────────────────────────────────────────────────
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PRC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_LoadStarSchema' AND schema_id = SCHEMA_ID('DW')" "$DB" | tr -d ' \r\n')
    [ "${PRC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ── Check: CSV file ──────────────────────────────────────────────────────────
CSV_EXISTS="false"
CSV_ROWS=0
CSV_HEADER=""
CSV_SIZE=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_CREATED_DURING_TASK="false"

CSV_PATH="/home/ga/Documents/exports/dw_revenue_summary.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_ROWS=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    CSV_SIZE=$(stat -c%s "$CSV_PATH" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c%Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ] 2>/dev/null; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# ── Build JSON result ─────────────────────────────────────────────────────────
cat > /tmp/star_schema_result.json << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "schema_exists": $SCHEMA_EXISTS,
    "dimdate_exists": $DIMDATE_EXISTS,
    "dimdate_rows": ${DIMDATE_ROWS:-0},
    "dimdate_cols": ${DIMDATE_COLS:-0},
    "dimdate_fy_test": ${DIMDATE_FY_TEST:-0},
    "dimdate_fq_test": ${DIMDATE_FQ_TEST:-0},
    "dimdate_weekend": ${DIMDATE_WEEKEND:--1},
    "dimprod_exists": $DIMPROD_EXISTS,
    "dimprod_rows": ${DIMPROD_ROWS:-0},
    "dimprod_has_sk": $DIMPROD_HAS_SK,
    "dimprod_uncategorized": ${DIMPROD_UNCAT:-0},
    "dimprod_general": ${DIMPROD_GENERAL:-0},
    "dimcust_exists": $DIMCUST_EXISTS,
    "dimcust_rows": ${DIMCUST_ROWS:-0},
    "dimcust_has_sk": $DIMCUST_HAS_SK,
    "dimcust_stores": ${DIMCUST_STORES:-0},
    "dimcust_individuals": ${DIMCUST_INDIVIDUALS:-0},
    "dimcust_store_prefix": ${DIMCUST_STORE_PREFIX:-0},
    "fact_exists": $FACT_EXISTS,
    "fact_rows": ${FACT_ROWS:-0},
    "fact_cols": ${FACT_COLS:-0},
    "fact_linetotal": ${FACT_LINETOTAL:-0.00},
    "ref_linetotal": ${REF_LINETOTAL:-0},
    "linetotal_diff": ${LINETOTAL_DIFF:-999999.99},
    "fact_tax": ${FACT_TAX:-0.00},
    "ref_tax": ${REF_TAX:-0},
    "tax_diff": ${TAX_DIFF:-999999.99},
    "fact_freight": ${FACT_FREIGHT:-0.00},
    "ref_freight": ${REF_FREIGHT:-0},
    "freight_diff": ${FREIGHT_DIFF:-999999.99},
    "orphan_prod": ${ORPHAN_PROD:--1},
    "orphan_cust": ${ORPHAN_CUST:--1},
    "orphan_odate": ${ORPHAN_ODATE:--1},
    "orphan_sdate": ${ORPHAN_SDATE:--1},
    "proc_exists": $PROC_EXISTS,
    "ref_products": ${REF_PRODUCTS:-0},
    "ref_customers": ${REF_CUSTOMERS:-0},
    "ref_lineitems": ${REF_LINEITEMS:-0},
    "ref_null_subcat": ${REF_NULL_SUBCAT:-0},
    "ref_store_only": ${REF_STORE_ONLY:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_header": "$CSV_HEADER",
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/star_schema_result.json 2>/dev/null || true
echo "Result saved to /tmp/star_schema_result.json"
cat /tmp/star_schema_result.json
echo ""
echo "=== Export complete ==="
exit 0
