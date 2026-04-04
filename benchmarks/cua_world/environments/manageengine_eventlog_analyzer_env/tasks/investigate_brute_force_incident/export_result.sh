#!/bin/bash
# Export script for investigate_brute_force_incident
# Captures: report file state, new alert count

echo "=== Exporting investigate_brute_force_incident Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

# Take final screenshot
take_screenshot /tmp/investigate_brute_force_incident_end.png

# --- Read baseline ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count 2>/dev/null | tr -d ' \n' || echo "0")

# Guard: ensure these are integers
echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0

# --- Check report file ---
REPORT_FILE="/home/ga/Desktop/incident_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
HAS_SERVICEACCT="false"
HAS_ATTACKER_IP="false"
HAS_REMEDIATION="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    # Check for correct targeted username
    if grep -qi "serviceacct" "$REPORT_FILE" 2>/dev/null; then
        HAS_SERVICEACCT="true"
    fi

    # Check for correct attacker IP
    if grep -q "192.168.10.45" "$REPORT_FILE" 2>/dev/null; then
        HAS_ATTACKER_IP="true"
    fi

    # Check for remediation content (any of multiple reasonable terms)
    if grep -qiE "remediat|recommend|mitigat|block|firewall|lockout|disable|password|reset" "$REPORT_FILE" 2>/dev/null; then
        HAS_REMEDIATION="true"
    fi
fi

# --- Count current alerts in ELA ---
CURRENT_ALERT_COUNT=0
ALERT_TABLES_FILE="/tmp/alert_table_names"
if [ -f "$ALERT_TABLES_FILE" ]; then
    while IFS= read -r TABLE; do
        TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
        [ -z "$TABLE" ] && continue
        COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
        if echo "$COUNT" | grep -qE '^[0-9]+$'; then
            CURRENT_ALERT_COUNT=$((CURRENT_ALERT_COUNT + COUNT))
        fi
    done < "$ALERT_TABLES_FILE"
else
    # Re-discover alert tables if file is missing
    ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
    for TABLE in $ALERT_TABLES; do
        TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
        [ -z "$TABLE" ] && continue
        COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
        if echo "$COUNT" | grep -qE '^[0-9]+$'; then
            CURRENT_ALERT_COUNT=$((CURRENT_ALERT_COUNT + COUNT))
        fi
    done
fi

NEW_ALERT_COUNT=$((CURRENT_ALERT_COUNT - INITIAL_ALERT_COUNT))
ALERT_CREATED="false"
if [ "$NEW_ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_CREATED="true"
fi

# --- Write result JSON ---
cat > /tmp/investigate_brute_force_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "task_start": $TASK_START,
    "has_serviceacct": $HAS_SERVICEACCT,
    "has_attacker_ip": $HAS_ATTACKER_IP,
    "has_remediation": $HAS_REMEDIATION,
    "initial_alert_count": $INITIAL_ALERT_COUNT,
    "current_alert_count": $CURRENT_ALERT_COUNT,
    "new_alert_count": $NEW_ALERT_COUNT,
    "alert_created": $ALERT_CREATED,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Report exists: $REPORT_EXISTS"
echo "Report size: $REPORT_SIZE bytes"
echo "Has serviceacct: $HAS_SERVICEACCT"
echo "Has attacker IP: $HAS_ATTACKER_IP"
echo "Alert created: $ALERT_CREATED (new=$NEW_ALERT_COUNT)"
echo "=== Export Complete ==="
