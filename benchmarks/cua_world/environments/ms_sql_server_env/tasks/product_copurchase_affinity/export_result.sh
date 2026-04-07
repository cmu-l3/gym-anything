#!/bin/bash
# Export results for product_copurchase_affinity task
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize JSON variables
TABLE_EXISTS="false"
PROC_EXISTS="false"
VIEW_EXISTS="false"
ROW_COUNT=0
COLUMNS_FOUND=""
HAS_REQUIRED_COLUMNS="false"
SUPPORT_VALID="true"
CONFIDENCE_VALID="true"
LIFT_VALID="true"
NO_DUPLICATE_PAIRS="true"
VIEW_RETURNS_DATA="false"
VIEW_FILTERS_LIFT="false"
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_MATCHES_DB="false"

# 1. Check Database Objects
if mssql_is_running; then
    # Check Table
    RES=$(mssql_query "SELECT COUNT(*) FROM sys.tables WHERE name = 'ProductAffinityResults'" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "$RES" -gt 0 ]; then
        TABLE_EXISTS="true"
        
        # Check Columns
        COLUMNS_FOUND=$(mssql_query "
            SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
            WHERE TABLE_NAME = 'ProductAffinityResults'
        " "AdventureWorks2022" | tr '\r\n' ',' | tr '[:upper:]' '[:lower:]')
        
        REQ_COLS=("producta_id" "productb_id" "cooccurrencecount" "support" "confidence_atob" "lift" "analysisdate")
        MISSING=0
        for col in "${REQ_COLS[@]}"; do
            if [[ "$COLUMNS_FOUND" != *"$col"* ]]; then
                MISSING=$((MISSING + 1))
            fi
        done
        if [ "$MISSING" -eq 0 ]; then
            HAS_REQUIRED_COLUMNS="true"
        fi

        # Check Row Count
        ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.ProductAffinityResults" "AdventureWorks2022" | tr -d ' \r\n')
        
        # Check Value Ranges (Anti-Gaming)
        BAD_SUPPORT=$(mssql_query "SELECT COUNT(*) FROM dbo.ProductAffinityResults WHERE Support < 0 OR Support > 1" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$BAD_SUPPORT" -gt 0 ] && SUPPORT_VALID="false"
        
        BAD_CONF=$(mssql_query "SELECT COUNT(*) FROM dbo.ProductAffinityResults WHERE Confidence_AtoB < 0 OR Confidence_AtoB > 1" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$BAD_CONF" -gt 0 ] && CONFIDENCE_VALID="false"
        
        BAD_LIFT=$(mssql_query "SELECT COUNT(*) FROM dbo.ProductAffinityResults WHERE Lift <= 0" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$BAD_LIFT" -gt 0 ] && LIFT_VALID="false"
        
        # Check Pair Duplication (A < B constraint)
        BAD_PAIRS=$(mssql_query "SELECT COUNT(*) FROM dbo.ProductAffinityResults WHERE ProductA_ID >= ProductB_ID" "AdventureWorks2022" | tr -d ' \r\n')
        [ "$BAD_PAIRS" -gt 0 ] && NO_DUPLICATE_PAIRS="false"
    fi
    
    # Check Procedure
    RES=$(mssql_query "SELECT COUNT(*) FROM sys.procedures WHERE name = 'usp_MarketBasketAnalysis'" "AdventureWorks2022" | tr -d ' \r\n')
    [ "$RES" -gt 0 ] && PROC_EXISTS="true"
    
    # Check View
    RES=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_TopProductBundles'" "AdventureWorks2022" | tr -d ' \r\n')
    if [ "$RES" -gt 0 ]; then
        VIEW_EXISTS="true"
        
        # Check View Data
        VIEW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_TopProductBundles" "AdventureWorks2022" | tr -d ' \r\n')
        if [ "$VIEW_COUNT" -gt 0 ]; then
            VIEW_RETURNS_DATA="true"
        fi
        
        # Check View Logic (Lift > 1)
        BAD_VIEW_ROWS=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_TopProductBundles WHERE Lift <= 1.0" "AdventureWorks2022" | tr -d ' \r\n')
        if [ "$BAD_VIEW_ROWS" -eq 0 ]; then
            VIEW_FILTERS_LIFT="true"
        fi
    fi
    
    # Get Top DB Result for CSV Cross-Check
    # Get the top pair string: "NameA|NameB"
    DB_TOP_PAIR=$(mssql_query "
        SELECT TOP 1 ProductA_Name + '|' + ProductB_Name 
        FROM dbo.vw_TopProductBundles 
        ORDER BY Lift DESC
    " "AdventureWorks2022" | tr -d '\r')
fi

# 2. Check CSV Export
CSV_PATH="/home/ga/Documents/exports/top_product_bundles.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count data lines (minus header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH")
    CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    
    # Simple cross-check: see if the top DB pair names appear in the CSV
    if [ -n "$DB_TOP_PAIR" ]; then
        NAME_A=$(echo "$DB_TOP_PAIR" | cut -d'|' -f1)
        NAME_B=$(echo "$DB_TOP_PAIR" | cut -d'|' -f2)
        if grep -Fq "$NAME_A" "$CSV_PATH" && grep -Fq "$NAME_B" "$CSV_PATH"; then
            CSV_MATCHES_DB="true"
        fi
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/affinity_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "table_exists": $TABLE_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "view_exists": $VIEW_EXISTS,
    "row_count": ${ROW_COUNT:-0},
    "has_required_columns": $HAS_REQUIRED_COLUMNS,
    "support_valid": $SUPPORT_VALID,
    "confidence_valid": $CONFIDENCE_VALID,
    "lift_valid": $LIFT_VALID,
    "no_duplicate_pairs": $NO_DUPLICATE_PAIRS,
    "view_returns_data": $VIEW_RETURNS_DATA,
    "view_filters_lift": $VIEW_FILTERS_LIFT,
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_matches_db": $CSV_MATCHES_DB,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="