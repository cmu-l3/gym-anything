#!/bin/bash
echo "=== Exporting Execute Explain Plan results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
OUTPUT_FILE_EXISTS=false
OUTPUT_FILE_SIZE=0
OUTPUT_HAS_PLAN=false
PLAN_HAS_JOIN=false
PLAN_HAS_WINDOW=false
PLAN_HAS_SORT=false
PLAN_TABLES_FOUND=""
SQL_DEVELOPER_RUNNING=false
QUERY_HAS_RANK=false
QUERY_HAS_DEPARTMENT=false
QUERY_HAS_SALARY=false
QUERY_HAS_TOP_N=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check for output file at exact path
OUTPUT_FILE="/home/ga/Documents/exports/explain_plan_output.txt"
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    OUTPUT_FILE_EXISTS=true
    OUTPUT_FILE_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo "0")

    # Check for explain plan operations
    if grep -qi "SELECT STATEMENT\|TABLE ACCESS\|INDEX\|HASH JOIN\|NESTED LOOPS\|MERGE JOIN\|SORT" "$OUTPUT_FILE" 2>/dev/null; then
        OUTPUT_HAS_PLAN=true
    fi

    if grep -qi "HASH JOIN\|NESTED LOOPS\|MERGE JOIN" "$OUTPUT_FILE" 2>/dev/null; then
        PLAN_HAS_JOIN=true
    fi

    if grep -qi "WINDOW\|RANK\|DENSE_RANK" "$OUTPUT_FILE" 2>/dev/null; then
        PLAN_HAS_WINDOW=true
    fi

    if grep -qi "SORT" "$OUTPUT_FILE" 2>/dev/null; then
        PLAN_HAS_SORT=true
    fi

    # Check which tables appear in plan
    TABLES_FOUND=""
    for tbl in EMPLOYEES DEPARTMENTS; do
        if grep -qi "$tbl" "$OUTPUT_FILE" 2>/dev/null; then
            if [ -z "$TABLES_FOUND" ]; then
                TABLES_FOUND="$tbl"
            else
                TABLES_FOUND="$TABLES_FOUND, $tbl"
            fi
        fi
    done
    PLAN_TABLES_FOUND="$TABLES_FOUND"

    # --- Query correctness checks ---
    # Check if file contains the SQL query text with ranking function
    if grep -qi "RANK\s*(\|DENSE_RANK\s*(\|ROW_NUMBER\s*(" "$OUTPUT_FILE" 2>/dev/null; then
        QUERY_HAS_RANK=true
    fi

    # Check if query references departments (join or subquery)
    if grep -qi "DEPARTMENT\|DEPT" "$OUTPUT_FILE" 2>/dev/null; then
        QUERY_HAS_DEPARTMENT=true
    fi

    # Check if query references salary
    if grep -qi "SALARY\|SAL" "$OUTPUT_FILE" 2>/dev/null; then
        QUERY_HAS_SALARY=true
    fi

    # Check for top-N filtering (ROWNUM, FETCH FIRST, WHERE rank <=)
    if grep -qi "ROWNUM\|FETCH FIRST\|<= *5\|< *6\|FETCH.*5\|LIMIT\|COUNT STOPKEY" "$OUTPUT_FILE" 2>/dev/null; then
        QUERY_HAS_TOP_N=true
    fi
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_file_size": $OUTPUT_FILE_SIZE,
    "output_has_plan": $OUTPUT_HAS_PLAN,
    "plan_has_join": $PLAN_HAS_JOIN,
    "plan_has_window": $PLAN_HAS_WINDOW,
    "plan_has_sort": $PLAN_HAS_SORT,
    "plan_tables_found": "$PLAN_TABLES_FOUND",
    "query_has_rank": $QUERY_HAS_RANK,
    "query_has_department": $QUERY_HAS_DEPARTMENT,
    "query_has_salary": $QUERY_HAS_SALARY,
    "query_has_top_n": $QUERY_HAS_TOP_N,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/explain_plan_result.json 2>/dev/null || sudo rm -f /tmp/explain_plan_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/explain_plan_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/explain_plan_result.json
chmod 666 /tmp/explain_plan_result.json 2>/dev/null || sudo chmod 666 /tmp/explain_plan_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/explain_plan_result.json"
cat /tmp/explain_plan_result.json
echo "=== Export complete ==="
