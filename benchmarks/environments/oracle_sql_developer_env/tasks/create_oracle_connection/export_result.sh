#!/bin/bash
# Export results for Create Oracle Connection task
echo "=== Exporting Create Oracle Connection results ==="

source /workspace/scripts/task_utils.sh

# Take screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize result variables
CONNECTION_CREATED=false
CONNECTION_NAME_FOUND=""
SQL_DEVELOPER_RUNNING=false
ORACLE_ACCESSIBLE=false
HR_TABLES_EXIST=false

# Check SQL Developer running
if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
    SQL_DEVELOPER_RUNNING=true
fi

# Check Oracle database accessible
EMP_COUNT=$(get_employee_count 2>/dev/null)
if [ -n "$EMP_COUNT" ] && [ "$EMP_COUNT" -gt 0 ] 2>/dev/null; then
    ORACLE_ACCESSIBLE=true
    HR_TABLES_EXIST=true
fi

# Check SQL Developer connection configuration
# SQL Developer 24.3 stores connections in connections.json (NOT connections.xml)
CONN_FILE=""
for dir in /home/ga/.sqldeveloper/system*/o.jdeveloper.db.connection*; do
    if [ -d "$dir" ]; then
        # Check for JSON first (SQL Developer 24.3+)
        if [ -f "$dir/connections.json" ]; then
            CONN_FILE="$dir/connections.json"
            break
        fi
        # Fallback to XML (older versions)
        for f in "$dir"/*.xml; do
            if [ -f "$f" ]; then
                CONN_FILE="$f"
                break 2
            fi
        done
    fi
done

# Fallback: search broadly
if [ -z "$CONN_FILE" ]; then
    CONN_FILE=$(find /home/ga/.sqldeveloper -name "connections.json" -type f 2>/dev/null | head -1)
fi
if [ -z "$CONN_FILE" ]; then
    CONN_FILE=$(find /home/ga/.sqldeveloper -name "connections.xml" -type f 2>/dev/null | head -1)
fi

if [ -n "$CONN_FILE" ] && [ -f "$CONN_FILE" ]; then
    echo "Found connection config: $CONN_FILE"

    # Look for XEPDB1 or hr connection references
    if grep -qi "XEPDB1\|HR Database\|localhost.*1521\|\"user\":\"hr\"" "$CONN_FILE" 2>/dev/null; then
        CONNECTION_CREATED=true
        # Extract connection name from JSON or XML
        CONNECTION_NAME_FOUND=$(grep -oP '"name"\s*:\s*"[^"]*"' "$CONN_FILE" 2>/dev/null | head -1 | sed 's/.*"name"\s*:\s*"//;s/".*//')
        if [ -z "$CONNECTION_NAME_FOUND" ]; then
            # Fallback for XML format
            CONNECTION_NAME_FOUND=$(grep -oP 'name="[^"]*"' "$CONN_FILE" 2>/dev/null | head -1 | cut -d'"' -f2)
        fi
        echo "Connection found: $CONNECTION_NAME_FOUND"
    fi
fi

# Count new connections since task started
INITIAL_COUNT=$(cat /tmp/initial_conn_count 2>/dev/null || echo "0")
CURRENT_COUNT=0
if [ -n "$CONN_FILE" ] && [ -f "$CONN_FILE" ]; then
    # Count connections in JSON format
    CURRENT_COUNT=$(grep -c '"name"' "$CONN_FILE" 2>/dev/null || true)
    if [ "$CURRENT_COUNT" -eq 0 ]; then
        # Fallback for XML format
        CURRENT_COUNT=$(grep -c '<Reference' "$CONN_FILE" 2>/dev/null || true)
    fi
fi
NEW_CONNECTIONS=$((CURRENT_COUNT - INITIAL_COUNT))

if [ "$NEW_CONNECTIONS" -gt 0 ] && [ "$CONNECTION_CREATED" != "true" ]; then
    CONNECTION_CREATED=true
    CONNECTION_NAME_FOUND="new_connection"
fi

# Collect GUI evidence
GUI_EVIDENCE=$(collect_gui_evidence 2>/dev/null || echo '"gui_evidence": {"sql_history_count": 0, "mru_connection_count": 0, "window_title": "", "window_title_changed": false, "sqldev_oracle_sessions": 0}')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sql_developer_running": $SQL_DEVELOPER_RUNNING,
    "connection_created": $CONNECTION_CREATED,
    "connection_name_found": "$CONNECTION_NAME_FOUND",
    "oracle_accessible": $ORACLE_ACCESSIBLE,
    "hr_tables_exist": $HR_TABLES_EXIST,
    "employee_count": ${EMP_COUNT:-0},
    "new_connections": $NEW_CONNECTIONS,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/connection_result.json 2>/dev/null || sudo rm -f /tmp/connection_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/connection_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/connection_result.json
chmod 666 /tmp/connection_result.json 2>/dev/null || sudo chmod 666 /tmp/connection_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/connection_result.json"
cat /tmp/connection_result.json
echo "=== Export complete ==="
