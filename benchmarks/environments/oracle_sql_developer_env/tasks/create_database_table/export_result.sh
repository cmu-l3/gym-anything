#!/bin/bash
# Export results for Create Database Table task
echo "=== Exporting Create Database Table results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize
TABLE_EXISTS=false
TABLE_ROW_COUNT=0
COLUMN_COUNT=0
HAS_PRIMARY_KEY=false
HAS_FOREIGN_KEY=false
FK_REFERENCES_DEPARTMENTS=false
COLUMNS_FOUND=""
SQL_DEVELOPER_RUNNING=false
TABLE_NEWLY_CREATED=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check if TRAINING_COURSES table exists
TABLE_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM user_tables WHERE table_name = 'TRAINING_COURSES';" "hr" | tr -d '[:space:]')
if [ "${TABLE_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TABLE_EXISTS=true

    # Get row count
    TABLE_ROW_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM training_courses;" "hr" | tr -d '[:space:]')

    # Get column info
    COLUMNS_FOUND=$(oracle_query_raw "SELECT column_name FROM user_tab_columns WHERE table_name = 'TRAINING_COURSES' ORDER BY column_id;" "hr" | tr '\n' ',' | sed 's/,$//')
    COLUMN_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tab_columns WHERE table_name = 'TRAINING_COURSES';" "hr" | tr -d '[:space:]')

    # Check for primary key
    PK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_constraints WHERE table_name = 'TRAINING_COURSES' AND constraint_type = 'P';" "hr" | tr -d '[:space:]')
    if [ "${PK_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        HAS_PRIMARY_KEY=true
    fi

    # Check for foreign key referencing DEPARTMENTS specifically
    FK_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_constraints WHERE table_name = 'TRAINING_COURSES' AND constraint_type = 'R';" "hr" | tr -d '[:space:]')
    if [ "${FK_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        HAS_FOREIGN_KEY=true
        # Verify FK references DEPARTMENTS table
        FK_REF_DEPT=$(oracle_query_raw "SELECT COUNT(*) FROM user_constraints tc JOIN user_constraints rc ON tc.r_constraint_name = rc.constraint_name WHERE tc.table_name = 'TRAINING_COURSES' AND tc.constraint_type = 'R' AND rc.table_name = 'DEPARTMENTS';" "hr" | tr -d '[:space:]')
        if [ "${FK_REF_DEPT:-0}" -gt 0 ] 2>/dev/null; then
            FK_REFERENCES_DEPARTMENTS=true
        fi
    fi
fi

# Check if table was newly created (anti-cheat)
INITIAL_TABLE_COUNT=$(cat /tmp/initial_table_count 2>/dev/null || echo "0")
CURRENT_TABLE_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM user_tables;" "hr" | tr -d '[:space:]')
if [ "$CURRENT_TABLE_COUNT" -gt "$INITIAL_TABLE_COUNT" ] 2>/dev/null; then
    TABLE_NEWLY_CREATED=true
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "table_exists": $TABLE_EXISTS,
    "table_row_count": ${TABLE_ROW_COUNT:-0},
    "column_count": ${COLUMN_COUNT:-0},
    "columns_found": "$COLUMNS_FOUND",
    "has_primary_key": $HAS_PRIMARY_KEY,
    "has_foreign_key": $HAS_FOREIGN_KEY,
    "fk_references_departments": $FK_REFERENCES_DEPARTMENTS,
    "table_newly_created": $TABLE_NEWLY_CREATED,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/table_result.json 2>/dev/null || sudo rm -f /tmp/table_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/table_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/table_result.json
chmod 666 /tmp/table_result.json 2>/dev/null || sudo chmod 666 /tmp/table_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/table_result.json"
cat /tmp/table_result.json
echo "=== Export complete ==="
