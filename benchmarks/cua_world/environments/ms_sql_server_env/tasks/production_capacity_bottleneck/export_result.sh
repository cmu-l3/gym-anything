#!/bin/bash
# Export script for production_capacity_bottleneck task

echo "=== Exporting Task Results ==="
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot of the agent's work
take_screenshot /tmp/task_final.png

# --- 1. Verify Scalar Function ---
FUNC_EXISTS="false"
FUNC_TEST_PASS="false"
if mssql_query "SELECT OBJECT_ID('dbo.fn_UtilizationRate')" | grep -q "[0-9]"; then
    FUNC_EXISTS="true"
    # Test logic: 80/100 = 0.8
    TEST_VAL=$(mssql_query "SELECT CAST(dbo.fn_UtilizationRate(80, 100) AS DECIMAL(10,2))")
    if echo "$TEST_VAL" | grep -q "0.80"; then
        FUNC_TEST_PASS="true"
    fi
fi

# --- 2. Verify View ---
VIEW_EXISTS="false"
VIEW_COLUMNS_MATCH="false"
VIEW_ROW_COUNT=0
if mssql_query "SELECT OBJECT_ID('dbo.vw_WorkCenterMonthlyMetrics')" | grep -q "[0-9]"; then
    VIEW_EXISTS="true"
    
    # Check for required columns
    COLS=$(mssql_query "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='vw_WorkCenterMonthlyMetrics'")
    if echo "$COLS" | grep -q "UtilizationRate" && \
       echo "$COLS" | grep -q "AvgCostVariancePct" && \
       echo "$COLS" | grep -q "AvgScheduleSlipDays"; then
        VIEW_COLUMNS_MATCH="true"
    fi
    
    # Check row count (should be substantial for 2013 data)
    VIEW_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM dbo.vw_WorkCenterMonthlyMetrics" | tr -d ' \r\n')
fi

# --- 3. Verify Table ---
TABLE_EXISTS="false"
TABLE_HAS_DATA="false"
TABLE_ROW_COUNT=0
RANK_CHECK_PASS="false"
if mssql_query "SELECT OBJECT_ID('Production.BottleneckAnalysis')" | grep -q "[0-9]"; then
    TABLE_EXISTS="true"
    TABLE_ROW_COUNT=$(mssql_query "SELECT COUNT(*) FROM Production.BottleneckAnalysis" | tr -d ' \r\n')
    
    if [ "$TABLE_ROW_COUNT" -gt 0 ]; then
        TABLE_HAS_DATA="true"
        
        # Check if Rank 1 exists
        if mssql_query "SELECT TOP 1 BottleneckRank FROM Production.BottleneckAnalysis WHERE BottleneckRank = 1" | grep -q "1"; then
            RANK_CHECK_PASS="true"
        fi
    fi
fi

# --- 4. Verify Stored Procedure ---
PROC_EXISTS="false"
if mssql_query "SELECT OBJECT_ID('dbo.usp_IdentifyBottlenecks')" | grep -q "[0-9]"; then
    PROC_EXISTS="true"
fi

# --- 5. Verify CSV Export ---
CSV_PATH="/home/ga/Documents/exports/bottleneck_report_2013.csv"
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_CONTENT_VALID="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count rows excluding header
    LINE_COUNT=$(wc -l < "$CSV_PATH")
    if [ "$LINE_COUNT" -gt 1 ]; then
        CSV_ROW_COUNT=$((LINE_COUNT - 1))
        
        # Check if it contains data that matches the DB table
        # Get top location from DB
        TOP_LOC_DB=$(mssql_query "SELECT TOP 1 LocationName FROM Production.BottleneckAnalysis ORDER BY BottleneckRank ASC" | tr -d '\r\n ')
        
        # Check if that location string is in the CSV
        if grep -q "$TOP_LOC_DB" "$CSV_PATH"; then
            CSV_CONTENT_VALID="true"
        fi
    fi
fi

# --- 6. Anti-Gaming / Logic Validation ---
# Calculate a reference utilization for Frame Forming (LocationID 10) in Jan 2013 to spot check values
# This helps ensure they didn't just hardcode numbers
REF_UTILIZATION=$(mssql_query "
    SELECT CAST(SUM(ActualResourceHrs) / (MAX(l.Availability) * 4.33) AS DECIMAL(5,2))
    FROM Production.WorkOrderRouting r
    JOIN Production.Location l ON r.LocationID = l.LocationID
    WHERE r.LocationID = 10 
    AND YEAR(ActualStartDate) = 2013 
    AND MONTH(ActualStartDate) = 1
" | tr -d ' \r\n')

# Fetch the agent's calculated value for the same
AGENT_UTILIZATION=$(mssql_query "
    SELECT CAST(UtilizationRate AS DECIMAL(5,2)) 
    FROM dbo.vw_WorkCenterMonthlyMetrics 
    WHERE LocationID = 10 AND CalendarYear = 2013 AND CalendarMonth = 1
" | tr -d ' \r\n')

LOGIC_VALID="false"
if [ "$REF_UTILIZATION" == "$AGENT_UTILIZATION" ] && [ -n "$REF_UTILIZATION" ]; then
    LOGIC_VALID="true"
fi

# Construct JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "func_exists": $FUNC_EXISTS,
    "func_test_pass": $FUNC_TEST_PASS,
    "view_exists": $VIEW_EXISTS,
    "view_columns_match": $VIEW_COLUMNS_MATCH,
    "view_row_count": ${VIEW_ROW_COUNT:-0},
    "table_exists": $TABLE_EXISTS,
    "table_has_data": $TABLE_HAS_DATA,
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "rank_check_pass": $RANK_CHECK_PASS,
    "proc_exists": $PROC_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_content_valid": $CSV_CONTENT_VALID,
    "logic_valid": $LOGIC_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save to final location
chmod 644 "$TEMP_JSON"
cp "$TEMP_JSON" /tmp/task_result.json
rm "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="