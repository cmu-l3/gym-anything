#!/bin/bash
# Export results for Metropolitan Crime Spree Detection task
echo "=== Exporting Crime Spree Detection results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Initialize tracking variables
SPREE_VW_EXISTS=false
SPREE_VW_ROWS=0
SPREE_VW_LOGIC_VALID=false

SLA_VW_EXISTS=false
SLA_VW_ROWS=0
SLA_VW_LOGIC_VALID=false

PIVOT_VW_EXISTS=false
PIVOT_VW_ROWS=0
PIVOT_VW_LOGIC_VALID=false

CSV_EXISTS=false
CSV_SIZE=0
CSV_COLUMNS_OK=false
CSV_CREATED_DURING_TASK=false

# ---------------------------------------------------------------
# 1. Verify SERIAL_CRIME_SPREES_VW
# ---------------------------------------------------------------
SPREE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'CRIME_ANALYST' AND view_name = 'SERIAL_CRIME_SPREES_VW';" "system" | tr -d '[:space:]')
if [ "${SPREE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SPREE_VW_EXISTS=true
    SPREE_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM crime_analyst.serial_crime_sprees_vw;" "system" | tr -d '[:space:]')
    SPREE_VW_ROWS=${SPREE_VW_ROWS:-0}

    # Extract view DDL to check for window function keywords
    SPREE_DDL=$(sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LONG 100000
SELECT DBMS_METADATA.GET_DDL('VIEW', 'SERIAL_CRIME_SPREES_VW', 'CRIME_ANALYST') FROM DUAL;
EXIT;
EOSQL
)
    if echo "$SPREE_DDL" | grep -qiE "RANGE\s+BETWEEN\s+INTERVAL.*72.*PRECEDING" 2>/dev/null; then
        SPREE_VW_LOGIC_VALID=true
    fi
fi

# ---------------------------------------------------------------
# 2. Verify RESPONSE_TIME_METRICS_VW
# ---------------------------------------------------------------
SLA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'CRIME_ANALYST' AND view_name = 'RESPONSE_TIME_METRICS_VW';" "system" | tr -d '[:space:]')
if [ "${SLA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SLA_VW_EXISTS=true
    SLA_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM crime_analyst.response_time_metrics_vw;" "system" | tr -d '[:space:]')
    SLA_VW_ROWS=${SLA_VW_ROWS:-0}

    # Extract view DDL to check for PERCENTILE_CONT
    SLA_DDL=$(sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LONG 100000
SELECT DBMS_METADATA.GET_DDL('VIEW', 'RESPONSE_TIME_METRICS_VW', 'CRIME_ANALYST') FROM DUAL;
EXIT;
EOSQL
)
    if echo "$SLA_DDL" | grep -qiE "PERCENTILE_CONT\s*\(\s*0?\.9\s*\)" 2>/dev/null; then
        SLA_VW_LOGIC_VALID=true
    fi
fi

# ---------------------------------------------------------------
# 3. Verify NIBRS_MONTHLY_PIVOT_VW
# ---------------------------------------------------------------
PIVOT_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'CRIME_ANALYST' AND view_name = 'NIBRS_MONTHLY_PIVOT_VW';" "system" | tr -d '[:space:]')
if [ "${PIVOT_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PIVOT_VW_EXISTS=true
    PIVOT_VW_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM crime_analyst.nibrs_monthly_pivot_vw;" "system" | tr -d '[:space:]')
    PIVOT_VW_ROWS=${PIVOT_VW_ROWS:-0}

    # Extract view DDL to check for PIVOT operator
    PIVOT_DDL=$(sudo docker exec -i oracle-xe sqlplus -s system/OraclePassword123@//localhost:1521/XEPDB1 << 'EOSQL'
SET HEADING OFF FEEDBACK OFF PAGESIZE 0 LONG 100000
SELECT DBMS_METADATA.GET_DDL('VIEW', 'NIBRS_MONTHLY_PIVOT_VW', 'CRIME_ANALYST') FROM DUAL;
EXIT;
EOSQL
)
    if echo "$PIVOT_DDL" | grep -qiE "\bPIVOT\b" 2>/dev/null; then
        PIVOT_VW_LOGIC_VALID=true
    fi
fi

# ---------------------------------------------------------------
# 4. Verify CSV Export
# ---------------------------------------------------------------
CSV_PATH="/home/ga/Documents/exports/nibrs_matrix.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Check creation time to prevent gaming
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK=true
    fi

    # Check for presence of required columns
    if head -1 "$CSV_PATH" | grep -qiE "HOMICIDE" && head -1 "$CSV_PATH" | grep -qiE "BURGLARY"; then
        CSV_COLUMNS_OK=true
    fi
fi

# ---------------------------------------------------------------
# 5. Collect GUI Evidence
# ---------------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence)

# ---------------------------------------------------------------
# 6. Build Result JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/crime_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "spree_vw_exists": $SPREE_VW_EXISTS,
    "spree_vw_rows": $SPREE_VW_ROWS,
    "spree_vw_logic_valid": $SPREE_VW_LOGIC_VALID,
    "sla_vw_exists": $SLA_VW_EXISTS,
    "sla_vw_rows": $SLA_VW_ROWS,
    "sla_vw_logic_valid": $SLA_VW_LOGIC_VALID,
    "pivot_vw_exists": $PIVOT_VW_EXISTS,
    "pivot_vw_rows": $PIVOT_VW_ROWS,
    "pivot_vw_logic_valid": $PIVOT_VW_LOGIC_VALID,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_columns_ok": $CSV_COLUMNS_OK,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    $GUI_EVIDENCE
}
EOF

# Move temp file safely
rm -f /tmp/crime_spree_result.json 2>/dev/null || sudo rm -f /tmp/crime_spree_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/crime_spree_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/crime_spree_result.json
chmod 666 /tmp/crime_spree_result.json 2>/dev/null || sudo chmod 666 /tmp/crime_spree_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/crime_spree_result.json"
cat /tmp/crime_spree_result.json
echo "=== Export Complete ==="