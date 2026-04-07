#!/bin/bash
# Export results for ar_payment_allocation_aging task
echo "=== Exporting AR Aging Task Results ==="

source /workspace/scripts/task_utils.sh

DISPLAY=:1 import -window root /tmp/task_end_screenshot.png 2>/dev/null || true

MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

ADS_RUNNING="false"
if ads_is_running; then ADS_RUNNING="true"; fi

# Read reference values from setup
TOTAL_PAYMENTS=$(grep "Total_Payments:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
PAYMENT_ROW_COUNT=$(grep "Payment_Row_Count:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
TOTAL_INVOICES=$(grep "Total_Invoices:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
TOTAL_TOTALDUE=$(grep "Total_TotalDue:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')
DISTINCT_CUSTOMERS=$(grep "Distinct_Customers:" /tmp/initial_state.txt 2>/dev/null | awk '{print $NF}')

DB="AdventureWorks2022"

# ============================================================
# Check: AR schema exists
# ============================================================
SCHEMA_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    SC=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'AR'" "$DB" | grep -v 'rows affected' | tr -d ' \r\n')
    [ "${SC:-0}" -gt 0 ] 2>/dev/null && SCHEMA_EXISTS="true"
fi

# ============================================================
# Check: AR.PaymentAllocation table
# ============================================================
ALLOC_TABLE_EXISTS="false"
ALLOC_ROW_COUNT=0
ALLOC_COLS=""
ALLOC_SUM="0.00"
RECONCILIATION_DIFF="999999.99"
NEGATIVE_ALLOC_COUNT=-1
CREDIT_BALANCE_ROWS=-1

if [ "$MSSQL_RUNNING" = "true" ]; then
    TC=$(mssql_query "SELECT CASE WHEN OBJECT_ID('AR.PaymentAllocation','U') IS NOT NULL THEN 1 ELSE 0 END" "$DB" | grep -v 'rows affected' | tr -d ' \r\n')
    [ "${TC:-0}" -gt 0 ] 2>/dev/null && ALLOC_TABLE_EXISTS="true"

    if [ "$ALLOC_TABLE_EXISTS" = "true" ]; then
        ALLOC_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM AR.PaymentAllocation" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        ALLOC_ROW_COUNT=${ALLOC_ROW_COUNT:-0}

        ALLOC_COLS=$(mssql_query "
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'AR' AND TABLE_NAME = 'PaymentAllocation'
        " "$DB" 2>/dev/null | tr '\r\n' ',' | sed 's/,$//')

        ALLOC_SUM=$(mssql_query "SELECT CAST(ISNULL(SUM(AllocatedAmount),0) AS DECIMAL(18,2)) FROM AR.PaymentAllocation" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        ALLOC_SUM=${ALLOC_SUM:-0.00}

        # Reconciliation check
        if [ -n "$TOTAL_PAYMENTS" ] && [ "$TOTAL_PAYMENTS" != "0" ]; then
            RECONCILIATION_DIFF=$(mssql_query "SELECT ABS(CAST('$ALLOC_SUM' AS DECIMAL(18,2)) - CAST('$TOTAL_PAYMENTS' AS DECIMAL(18,2)))" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
            RECONCILIATION_DIFF=${RECONCILIATION_DIFF:-999999.99}
        fi

        # Check for negative allocations
        NEGATIVE_ALLOC_COUNT=$(mssql_query "SELECT COUNT(*) FROM AR.PaymentAllocation WHERE AllocatedAmount < 0" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        NEGATIVE_ALLOC_COUNT=${NEGATIVE_ALLOC_COUNT:--1}

        # Check for credit balance rows (SalesOrderID = -1)
        CREDIT_BALANCE_ROWS=$(mssql_query "SELECT COUNT(*) FROM AR.PaymentAllocation WHERE SalesOrderID = -1" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        CREDIT_BALANCE_ROWS=${CREDIT_BALANCE_ROWS:--1}
    fi
fi

# ============================================================
# Check: Over-allocation per invoice
# ============================================================
OVER_ALLOC_COUNT=-1
if [ "$ALLOC_TABLE_EXISTS" = "true" ] && [ "$MSSQL_RUNNING" = "true" ]; then
    OVER_ALLOC_COUNT=$(mssql_query "
        SELECT COUNT(*)
        FROM (
            SELECT pa.SalesOrderID, SUM(pa.AllocatedAmount) AS TotalAlloc, h.TotalDue
            FROM AR.PaymentAllocation pa
            JOIN Sales.SalesOrderHeader h ON pa.SalesOrderID = h.SalesOrderID
            WHERE pa.SalesOrderID > 0
            GROUP BY pa.SalesOrderID, h.TotalDue
            HAVING SUM(pa.AllocatedAmount) > h.TotalDue + 0.01
        ) x
    " "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
    OVER_ALLOC_COUNT=${OVER_ALLOC_COUNT:--1}
fi

# ============================================================
# Check: FIFO ordering spot-check (3 customers)
# ============================================================
FIFO_CHECK="unknown"
if [ "$ALLOC_TABLE_EXISTS" = "true" ] && [ "$MSSQL_RUNNING" = "true" ]; then
    # Check that for a sample customer, allocations go to older invoices first
    # A violation is when a newer invoice gets allocation before an older one that still has balance
    FIFO_VIOLATIONS=$(mssql_query "
        WITH SampleCustomers AS (
            SELECT TOP 3 CustomerID
            FROM AR.PaymentAllocation pa
            WHERE pa.SalesOrderID > 0
            GROUP BY CustomerID
            HAVING COUNT(DISTINCT SalesOrderID) >= 3
            ORDER BY CustomerID
        ),
        AllocWithOrder AS (
            SELECT pa.SalesOrderID, pa.AllocatedAmount, h.OrderDate, h.CustomerID,
                   ROW_NUMBER() OVER (PARTITION BY h.CustomerID ORDER BY pa.AllocationID) AS AllocSeq
            FROM AR.PaymentAllocation pa
            JOIN Sales.SalesOrderHeader h ON pa.SalesOrderID = h.SalesOrderID
            WHERE h.CustomerID IN (SELECT CustomerID FROM SampleCustomers)
              AND pa.SalesOrderID > 0
        )
        SELECT COUNT(*)
        FROM AllocWithOrder a1
        JOIN AllocWithOrder a2 ON a1.CustomerID = a2.CustomerID
            AND a1.AllocSeq < a2.AllocSeq
            AND a1.OrderDate > a2.OrderDate
            AND a1.SalesOrderID <> a2.SalesOrderID
    " "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
    FIFO_VIOLATIONS=${FIFO_VIOLATIONS:-unknown}
    if [ "$FIFO_VIOLATIONS" = "0" ]; then
        FIFO_CHECK="pass"
    else
        FIFO_CHECK="fail_${FIFO_VIOLATIONS}"
    fi
fi

# ============================================================
# Check: AR.usp_AllocatePayments stored procedure
# ============================================================
PROC_EXISTS="false"
if [ "$MSSQL_RUNNING" = "true" ]; then
    PRC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_AllocatePayments' AND schema_id = SCHEMA_ID('AR')" "$DB" | grep -v 'rows affected' | tr -d ' \r\n')
    [ "${PRC:-0}" -gt 0 ] 2>/dev/null && PROC_EXISTS="true"
fi

# ============================================================
# Check: AR.vw_InvoiceOpenBalance view
# ============================================================
VIEW_EXISTS="false"
VIEW_ROW_COUNT=0
VIEW_COLS=""

if [ "$MSSQL_RUNNING" = "true" ]; then
    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_InvoiceOpenBalance' AND schema_id = SCHEMA_ID('AR')" "$DB" | grep -v 'rows affected' | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] 2>/dev/null && VIEW_EXISTS="true"

    if [ "$VIEW_EXISTS" = "true" ]; then
        VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM AR.vw_InvoiceOpenBalance" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        VIEW_ROW_COUNT=${VIEW_ROW_COUNT:-0}

        VIEW_COLS=$(mssql_query "
            SELECT COLUMN_NAME
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'AR' AND TABLE_NAME = 'vw_InvoiceOpenBalance'
        " "$DB" 2>/dev/null | tr '\r\n' ',' | sed 's/,$//')
    fi
fi

# ============================================================
# Check: AR.fn_AgingBuckets inline TVF
# ============================================================
TVF_EXISTS="false"
TVF_ROW_COUNT=0

if [ "$MSSQL_RUNNING" = "true" ]; then
    # Check for inline TVF (type = 'IF')
    TF=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE name = 'fn_AgingBuckets' AND schema_id = SCHEMA_ID('AR') AND type IN ('IF','TF','FN')" "$DB" | grep -v 'rows affected' | tr -d ' \r\n')
    [ "${TF:-0}" -gt 0 ] 2>/dev/null && TVF_EXISTS="true"

    if [ "$TVF_EXISTS" = "true" ]; then
        TVF_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM AR.fn_AgingBuckets('2014-06-30')" "$DB" 2>/dev/null | grep -v 'rows affected' | tr -d ' \r\n'; true)
        TVF_ROW_COUNT=${TVF_ROW_COUNT:-0}
    fi
fi

# ============================================================
# Check: CSV export
# ============================================================
CSV_EXISTS="false"
CSV_ROWS=0
CSV_HEADER=""
CSV_SIZE=0
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CSV_CREATED_DURING_TASK="false"

CSV_PATH="/home/ga/Documents/exports/ar_aging_report.csv"
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

# ============================================================
# Build JSON result
# ============================================================
TEMP_JSON=$(mktemp /tmp/ar_aging_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "ads_running": $ADS_RUNNING,
    "schema_exists": $SCHEMA_EXISTS,
    "alloc_table_exists": $ALLOC_TABLE_EXISTS,
    "alloc_row_count": ${ALLOC_ROW_COUNT:-0},
    "alloc_columns": "$ALLOC_COLS",
    "alloc_sum": ${ALLOC_SUM:-0.00},
    "total_payments": ${TOTAL_PAYMENTS:-0},
    "reconciliation_diff": ${RECONCILIATION_DIFF:-999999.99},
    "negative_alloc_count": ${NEGATIVE_ALLOC_COUNT:--1},
    "credit_balance_rows": ${CREDIT_BALANCE_ROWS:--1},
    "over_alloc_count": ${OVER_ALLOC_COUNT:--1},
    "fifo_check": "$FIFO_CHECK",
    "proc_exists": $PROC_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "view_columns": "$VIEW_COLS",
    "tvf_exists": $TVF_EXISTS,
    "tvf_row_count": ${TVF_ROW_COUNT:-0},
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_header": "$CSV_HEADER",
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "payment_row_count": ${PAYMENT_ROW_COUNT:-0},
    "total_invoices": ${TOTAL_INVOICES:-0},
    "total_totaldue": ${TOTAL_TOTALDUE:-0},
    "distinct_customers": ${DISTINCT_CUSTOMERS:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/ar_aging_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ar_aging_result.json
chmod 666 /tmp/ar_aging_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Also copy to the standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/ar_aging_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/ar_aging_result.json"
cat /tmp/ar_aging_result.json
echo ""
echo "=== Export complete ==="
exit 0
