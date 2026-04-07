#!/bin/bash
# Export results for External Table Cost Analysis task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check Output File ---
OUTPUT_FILE="/home/ga/Desktop/cost_analysis_report.txt"
FILE_EXISTS="false"
FILE_SIZE=0
FILE_LINES=0
FILE_HAS_SALARY="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check for some expected content (salary numbers)
    if grep -qE "[0-9]{4,}" "$OUTPUT_FILE"; then
        FILE_HAS_SALARY="true"
    fi
fi

# --- 2. Query Database State ---
# We use Python/cx_Oracle (oracledb) logic via docker exec or piping to sqlplus 
# to build a comprehensive JSON result.

echo "Querying database state..."

# Construct SQL to check objects
# Using a complex SQL block to generate JSON-like structure or just discrete checks
# We'll use python inside the container if available or simple sqlplus queries

# Check Ext Table 1
TBL1_EXISTS=$(record_exists "user_tables" "table_name='EXT_COUNTRY_COSTS'" "hr" && echo "true" || echo "false")
TBL1_IS_EXT=$(record_exists "user_external_tables" "table_name='EXT_COUNTRY_COSTS'" "hr" && echo "true" || echo "false")
TBL1_COUNT="0"
if [ "$TBL1_EXISTS" = "true" ]; then
    TBL1_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM ext_country_costs;" "hr" 2>/dev/null | tr -d ' ' || echo "0")
fi

# Check Ext Table 2
TBL2_EXISTS=$(record_exists "user_tables" "table_name='EXT_MARKET_SALARIES'" "hr" && echo "true" || echo "false")
TBL2_IS_EXT=$(record_exists "user_external_tables" "table_name='EXT_MARKET_SALARIES'" "hr" && echo "true" || echo "false")
TBL2_COUNT="0"
if [ "$TBL2_EXISTS" = "true" ]; then
    TBL2_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM ext_market_salaries;" "hr" 2>/dev/null | tr -d ' ' || echo "0")
fi

# Check View
VIEW_EXISTS=$(record_exists "user_views" "view_name='EMPLOYEE_COST_ANALYSIS'" "hr" && echo "true" || echo "false")
VIEW_COUNT="0"
VIEW_TEXT=""
VIEW_COLS=""

if [ "$VIEW_EXISTS" = "true" ]; then
    VIEW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employee_cost_analysis;" "hr" 2>/dev/null | tr -d ' ' || echo "0")
    
    # Check if view definition references the external tables (Anti-gaming)
    # user_views.text is LONG type, tricky in SQLPlus. 
    # We check dependencies instead
    VIEW_DEPS=$(oracle_query_raw "
        SELECT count(*) 
        FROM user_dependencies 
        WHERE name='EMPLOYEE_COST_ANALYSIS' 
        AND referenced_name IN ('EXT_COUNTRY_COSTS', 'EXT_MARKET_SALARIES');
    " "hr" | tr -d ' ')
    
    # Check columns
    VIEW_COLS=$(oracle_query_raw "
        SELECT column_name FROM user_tab_columns 
        WHERE table_name='EMPLOYEE_COST_ANALYSIS' 
        ORDER BY column_id;
    " "hr" | tr '\n' ',' || echo "")
fi

# Start/End times
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
END_TIME=$(date +%s)

# Create JSON Result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $START_TIME,
    "task_end": $END_TIME,
    "output_file": {
        "exists": $FILE_EXISTS,
        "size_bytes": $FILE_SIZE,
        "line_count": $FILE_LINES,
        "has_salary_data": $FILE_HAS_SALARY
    },
    "database_objects": {
        "ext_country_costs": {
            "exists": $TBL1_EXISTS,
            "is_external": $TBL1_IS_EXT,
            "row_count": ${TBL1_COUNT:-0}
        },
        "ext_market_salaries": {
            "exists": $TBL2_EXISTS,
            "is_external": $TBL2_IS_EXT,
            "row_count": ${TBL2_COUNT:-0}
        },
        "employee_cost_analysis_view": {
            "exists": $VIEW_EXISTS,
            "row_count": ${VIEW_COUNT:-0},
            "dependency_count": ${VIEW_DEPS:-0},
            "columns": "$VIEW_COLS"
        }
    }
}
EOF

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="