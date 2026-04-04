#!/bin/bash
# Export results for Query Employee Salary task
echo "=== Exporting Query Employee Salary results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
OUTPUT_FILE_EXISTS=false
OUTPUT_ROW_COUNT=0
CORRECT_COUNT=false
KNOWN_EMPLOYEES_MATCHED=0
EMPLOYEES_FOUND=""
SQL_DEVELOPER_RUNNING=false
QUERY_EXECUTED=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check for output file at the EXACT specified path only
OUTPUT_FILE="/home/ga/Documents/exports/finance_high_salary.csv"
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_EXISTS=true

    # Count data rows (excluding header)
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    # Check if first line looks like a header
    FIRST_LINE=$(head -1 "$OUTPUT_FILE" 2>/dev/null)
    if echo "$FIRST_LINE" | grep -qi "first_name\|last_name\|salary\|employee\|name"; then
        OUTPUT_ROW_COUNT=$((TOTAL_LINES - 1))
    else
        OUTPUT_ROW_COUNT=$TOTAL_LINES
    fi

    # Check if count matches expected (exactly 5 employees)
    if [ "$OUTPUT_ROW_COUNT" -eq 5 ]; then
        CORRECT_COUNT=true
    fi

    # Validate known employees in output
    KNOWN_NAMES=("Greenberg" "Faviet" "Chen" "Sciarra" "Urman")
    for name in "${KNOWN_NAMES[@]}"; do
        if grep -qi "$name" "$OUTPUT_FILE" 2>/dev/null; then
            KNOWN_EMPLOYEES_MATCHED=$((KNOWN_EMPLOYEES_MATCHED + 1))
            if [ -z "$EMPLOYEES_FOUND" ]; then
                EMPLOYEES_FOUND="$name"
            else
                EMPLOYEES_FOUND="$EMPLOYEES_FOUND, $name"
            fi
        fi
    done

    if [ "$KNOWN_EMPLOYEES_MATCHED" -gt 0 ]; then
        QUERY_EXECUTED=true
    fi
fi

# Ground truth verification from database
DB_RESULT_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM employees WHERE department_id = 100 AND salary > 7000;" "hr" 2>/dev/null | tr -d '[:space:]')

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_path": "$OUTPUT_FILE",
    "output_row_count": $OUTPUT_ROW_COUNT,
    "correct_count": $CORRECT_COUNT,
    "known_employees_matched": $KNOWN_EMPLOYEES_MATCHED,
    "employees_found": "$EMPLOYEES_FOUND",
    "query_executed": $QUERY_EXECUTED,
    "db_result_count": ${DB_RESULT_COUNT:-0},
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/salary_query_result.json 2>/dev/null || sudo rm -f /tmp/salary_query_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/salary_query_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/salary_query_result.json
chmod 666 /tmp/salary_query_result.json 2>/dev/null || sudo chmod 666 /tmp/salary_query_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/salary_query_result.json"
cat /tmp/salary_query_result.json
echo "=== Export complete ==="
