#!/bin/bash
# Export results for sales_quota_attainment_history
echo "=== Exporting task result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Task metadata
VIEW_NAME="Sales.vw_HistoricalQuotaAttainment"
CSV_PATH="/home/ga/Documents/quota_attainment_2012.csv"
TEST_PERSON_ID=275
TEST_DATE="2011-05-31 00:00:00.000"

# 1. Check if View Exists
VIEW_EXISTS=$(mssql_query "SELECT COUNT(*) FROM sys.views WHERE name = 'vw_HistoricalQuotaAttainment' AND schema_id = SCHEMA_ID('Sales')" | tr -d ' \r\n')
[ -z "$VIEW_EXISTS" ] && VIEW_EXISTS=0

# 2. Check Columns
COLUMNS_FOUND=""
if [ "$VIEW_EXISTS" -eq 1 ]; then
    COLUMNS_FOUND=$(mssql_query "
        SELECT COLUMN_NAME 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_SCHEMA='Sales' AND TABLE_NAME='vw_HistoricalQuotaAttainment'
        ORDER BY ORDINAL_POSITION
    " | tr -d '\r' | tr '\n' ',' | sed 's/,$//')
fi

# 3. Validation Query: Ground Truth vs Agent View
# We calculate the ground truth for a specific tricky record (Michael Blythe, 2011-05-31)
# Tricky because: It's in the middle of history, needs correct range join.
GT_ACTUAL_SALES=0
GT_ATTAINMENT=0
AGENT_ACTUAL_SALES=0
AGENT_ATTAINMENT=0
AGENT_QUOTA_END=""

if [ "$VIEW_EXISTS" -eq 1 ]; then
    # Calculate Ground Truth in bash/sql independently
    # Logic: Get range [2011-05-31, NextQuotaDate), sum SubTotal
    GT_DATA=$(mssql_query "
        WITH QuotaRanges AS (
            SELECT 
                BusinessEntityID, 
                QuotaDate AS StartDate,
                LEAD(QuotaDate, 1, GETDATE()) OVER (PARTITION BY BusinessEntityID ORDER BY QuotaDate) AS EndDate,
                SalesQuota
            FROM Sales.SalesPersonQuotaHistory
        )
        SELECT 
            ISNULL(SUM(soh.SubTotal), 0),
            CASE WHEN MAX(q.SalesQuota) > 0 
                 THEN (ISNULL(SUM(soh.SubTotal), 0) / MAX(q.SalesQuota)) * 100 
                 ELSE 0 END
        FROM QuotaRanges q
        LEFT JOIN Sales.SalesOrderHeader soh 
            ON soh.SalesPersonID = q.BusinessEntityID 
            AND soh.OrderDate >= q.StartDate 
            AND soh.OrderDate < q.EndDate
        WHERE q.BusinessEntityID = $TEST_PERSON_ID 
          AND q.StartDate = '$TEST_DATE'
    ")
    
    # Parse GT Data (SQLCMD output can be whitespace heavy)
    GT_ACTUAL_SALES=$(echo "$GT_DATA" | head -n 3 | tail -n 1 | awk '{print $1}')
    GT_ATTAINMENT=$(echo "$GT_DATA" | head -n 3 | tail -n 1 | awk '{print $2}')
    
    # Get Agent's View Data for same record
    AGENT_DATA=$(mssql_query "
        SELECT 
            ActualSales, 
            AttainmentPct,
            CONVERT(varchar, QuotaEndDate, 120)
        FROM Sales.vw_HistoricalQuotaAttainment
        WHERE BusinessEntityID = $TEST_PERSON_ID 
          AND QuotaStartDate = '$TEST_DATE'
    ")
    
    AGENT_ACTUAL_SALES=$(echo "$AGENT_DATA" | head -n 3 | tail -n 1 | awk '{print $1}')
    AGENT_ATTAINMENT=$(echo "$AGENT_DATA" | head -n 3 | tail -n 1 | awk '{print $2}')
    AGENT_QUOTA_END=$(echo "$AGENT_DATA" | head -n 3 | tail -n 1 | awk '{print $3" "$4}')
fi

# 4. Check CSV File
CSV_EXISTS="false"
CSV_ROW_COUNT=0
CSV_CONTENT_VALID="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    # Count rows excluding header
    CSV_ROW_COUNT=$(tail -n +2 "$CSV_PATH" | wc -l)
    
    # Check if dates in CSV are actually 2012 (simple grep check)
    if grep -q "2012-" "$CSV_PATH"; then
        CSV_CONTENT_VALID="true"
    fi
fi

# 5. Check Output File Timestamp (Anti-Gaming)
FILE_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    FILE_TIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Prepare Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "view_exists": $VIEW_EXISTS,
    "columns_found": "$COLUMNS_FOUND",
    "test_case": {
        "person_id": $TEST_PERSON_ID,
        "date": "$TEST_DATE",
        "gt_actual": "$GT_ACTUAL_SALES",
        "gt_attainment": "$GT_ATTAINMENT",
        "agent_actual": "$AGENT_ACTUAL_SALES",
        "agent_attainment": "$AGENT_ATTAINMENT",
        "agent_quota_end": "$AGENT_QUOTA_END"
    },
    "csv_file": {
        "exists": $CSV_EXISTS,
        "row_count": $CSV_ROW_COUNT,
        "content_valid": $CSV_CONTENT_VALID,
        "created_during_task": $FILE_CREATED_DURING_TASK
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result Exported:"
cat /tmp/task_result.json
echo "=== Export Complete ==="