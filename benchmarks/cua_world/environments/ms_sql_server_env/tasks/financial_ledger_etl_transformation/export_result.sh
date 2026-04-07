#!/bin/bash
# Export results for financial_ledger_etl_transformation task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Check if SQL Server is running
MSSQL_RUNNING="false"
if mssql_is_running; then MSSQL_RUNNING="true"; fi

# 1. Check Infrastructure (Schema, Tables, Proc, View)
SCHEMA_EXISTS="false"
COA_EXISTS="false"
GL_EXISTS="false"
PROC_EXISTS="false"
VIEW_EXISTS="false"

if [ "$MSSQL_RUNNING" = "true" ]; then
    SC=$(mssql_query "SELECT COUNT(*) FROM sys.schemas WHERE name = 'Finance'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${SC:-0}" -gt 0 ] && SCHEMA_EXISTS="true"

    TC1=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Finance.ChartOfAccounts') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${TC1:-0}" -gt 0 ] && COA_EXISTS="true"

    TC2=$(mssql_query "SELECT COUNT(*) FROM sys.objects WHERE object_id = OBJECT_ID('Finance.GeneralLedger') AND type = 'U'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${TC2:-0}" -gt 0 ] && GL_EXISTS="true"

    PC=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_PostSalesToGL' AND schema_id = SCHEMA_ID('Finance')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${PC:-0}" -gt 0 ] && PROC_EXISTS="true"

    VC=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_UnbalancedTransactions' AND schema_id = SCHEMA_ID('Finance')" "AdventureWorks2022" | tr -d ' \r\n')
    [ "${VC:-0}" -gt 0 ] && VIEW_EXISTS="true"
fi

# 2. Validate Chart of Accounts Seeding
COA_COUNT=0
REQUIRED_ACCOUNTS_FOUND=0
if [ "$COA_EXISTS" = "true" ]; then
    COA_COUNT=$(mssql_query "SELECT COUNT(*) FROM Finance.ChartOfAccounts" "AdventureWorks2022" | tr -d ' \r\n')
    # Check for specific required codes
    REQUIRED_ACCOUNTS_FOUND=$(mssql_query "
        SELECT COUNT(*) FROM Finance.ChartOfAccounts 
        WHERE AccountCode IN (1100, 2100, 4001, 4002, 4003, 4004, 4100)
    " "AdventureWorks2022" | tr -d ' \r\n')
fi

# 3. Validate General Ledger Population & Logic
GL_ROW_COUNT=0
BALANCE_DIFF=0
AR_TOTAL=0
REV_TOTAL=0
TAX_TOTAL=0
FREIGHT_TOTAL=0
LOGIC_CHECK_PASSED="false"
ZERO_VAL_CHECK_PASSED="false"

if [ "$GL_EXISTS" = "true" ]; then
    GL_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Finance.GeneralLedger" "AdventureWorks2022" | tr -d ' \r\n')
    
    # Check Global Balance (Sum Debits - Sum Credits should be 0)
    BALANCE_DIFF=$(mssql_query "
        SELECT CAST(ABS(SUM(Debit) - SUM(Credit)) AS DECIMAL(10,2)) 
        FROM Finance.GeneralLedger
    " "AdventureWorks2022" | tr -d ' \r\n')
    
    # Logic Check: Pick one order (e.g. SalesOrderID 51081 from Q1 2013)
    # 51081 is usually in North America (Territory 1). Expected Revenue Account: 4001.
    SAMPLE_CHECK=$(mssql_query "
        SELECT COUNT(*)
        FROM Finance.GeneralLedger gl
        JOIN Sales.SalesOrderHeader soh ON gl.SalesOrderID = soh.SalesOrderID
        JOIN Sales.SalesTerritory st ON soh.TerritoryID = st.TerritoryID
        WHERE gl.Credit > 0 
          AND st.[Group] = 'North America' 
          AND gl.AccountCode = 4001
    " "AdventureWorks2022" | tr -d ' \r\n')
    
    if [ "${SAMPLE_CHECK:-0}" -gt 0 ]; then
        LOGIC_CHECK_PASSED="true"
    fi

    # Check that we don't have 0.00 entries (instruction said "if > 0")
    ZERO_ENTRIES=$(mssql_query "SELECT COUNT(*) FROM Finance.GeneralLedger WHERE Debit = 0 AND Credit = 0" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "${ZERO_ENTRIES:-0}" -eq 0 ]; then
        ZERO_VAL_CHECK_PASSED="true"
    fi
fi

# 4. Audit View Check
VIEW_RETURNS_ROWS="false"
if [ "$VIEW_EXISTS" = "true" ]; then
    # The view should return NO rows if data is balanced
    IMBALANCE_COUNT=$(mssql_query "SELECT COUNT(*) FROM Finance.vw_UnbalancedTransactions" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "${IMBALANCE_COUNT:-0}" -eq 0 ]; then
        VIEW_RETURNS_ROWS="false" # Good result
    else
        VIEW_RETURNS_ROWS="true" # Bad result
    fi
fi

# 5. Check Constraints (Positive Money)
CONSTRAINTS_EXIST="false"
if [ "$GL_EXISTS" = "true" ]; then
    CC_COUNT=$(mssql_query "
        SELECT COUNT(*) FROM sys.check_constraints 
        WHERE parent_object_id = OBJECT_ID('Finance.GeneralLedger')
    " "AdventureWorks2022" | tr -d ' \r\n')
    if [ "${CC_COUNT:-0}" -gt 0 ]; then
        CONSTRAINTS_EXIST="true"
    fi
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/financial_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "mssql_running": $MSSQL_RUNNING,
    "schema_exists": $SCHEMA_EXISTS,
    "coa_exists": $COA_EXISTS,
    "gl_exists": $GL_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "coa_count": ${COA_COUNT:-0},
    "required_accounts_found": ${REQUIRED_ACCOUNTS_FOUND:-0},
    "gl_row_count": ${GL_ROW_COUNT:-0},
    "balance_diff": ${BALANCE_DIFF:-999},
    "logic_check_passed": $LOGIC_CHECK_PASSED,
    "zero_val_check_passed": $ZERO_VAL_CHECK_PASSED,
    "view_returns_rows": $VIEW_RETURNS_ROWS,
    "constraints_exist": $CONSTRAINTS_EXIST,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/financial_etl_result.json 2>/dev/null || sudo rm -f /tmp/financial_etl_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/financial_etl_result.json
chmod 666 /tmp/financial_etl_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/financial_etl_result.json"
cat /tmp/financial_etl_result.json
echo ""
echo "=== Export Complete ==="