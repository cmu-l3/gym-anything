#!/bin/bash
# Export script for configure_hipaa_compliance_monitoring

echo "=== Exporting configure_hipaa_compliance_monitoring Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

take_screenshot /tmp/configure_hipaa_compliance_end.png

# --- Baseline ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count_hipaa 2>/dev/null | tr -d ' \n' || echo "0")
echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0

# --- Check HIPAA report file ---
REPORT_FILE="/home/ga/Desktop/hipaa_compliance_report.html"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
HAS_HIPAA_VOCAB="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Check for HIPAA-specific vocabulary that only appears when navigating the compliance section
    if grep -qiE "hipaa|health insurance portability|accountability act|phi|protected health|164\." "$REPORT_FILE" 2>/dev/null; then
        HAS_HIPAA_VOCAB="true"
    fi
fi

# --- Check for PHI alert profile created ---
CURRENT_ALERT_COUNT=0
PHI_ALERT_FOUND="false"

ALERT_TABLES_FILE="/tmp/alert_table_names_hipaa"
ALERT_TABLES=""
if [ -f "$ALERT_TABLES_FILE" ]; then
    ALERT_TABLES=$(cat "$ALERT_TABLES_FILE")
else
    ALERT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%alert%'" 2>/dev/null)
fi

for TABLE in $ALERT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        CURRENT_ALERT_COUNT=$((CURRENT_ALERT_COUNT + COUNT))
    fi
    # Look for PHI-related alert name in this table
    # Try common column names for alert name
    for COL in alertname alert_name name rulename rule_name title; do
        PHI_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $COL ILIKE '%phi%' OR $COL ILIKE '%unauthorized%' OR $COL ILIKE '%hipaa%' OR $COL ILIKE '%patient%'" 2>/dev/null | tr -d ' ')
        if echo "$PHI_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            PHI_ALERT_FOUND="true"
            break 2
        fi
    done
done

NEW_ALERT_COUNT=$((CURRENT_ALERT_COUNT - INITIAL_ALERT_COUNT))
ALERT_CREATED="false"
if [ "$NEW_ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_CREATED="true"
fi

# --- Check log retention setting ---
# Try multiple possible locations for retention config
LOG_RETENTION_DAYS=0
RETENTION_SET="false"

# Try common table/column combos with fallback
for TABLE_QUERY in \
    "SELECT value FROM globalconfig WHERE name='logRetentionDays'" \
    "SELECT value FROM serverconfig WHERE configname='logRetentionDays'" \
    "SELECT configvalue FROM logconfig WHERE configkey ILIKE '%retention%'" \
    "SELECT value FROM ela_config WHERE key ILIKE '%retention%'" \
    "SELECT retentionperiod FROM logsettings LIMIT 1"; do
    RESULT=$(ela_db_query "$TABLE_QUERY" 2>/dev/null | tr -d ' ')
    if echo "$RESULT" | grep -qE '^[0-9]+$'; then
        LOG_RETENTION_DAYS=$RESULT
        if [ "$LOG_RETENTION_DAYS" -ge 2555 ] 2>/dev/null; then
            RETENTION_SET="true"
        fi
        break
    fi
done

# Write result JSON
cat > /tmp/configure_hipaa_compliance_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "task_start": $TASK_START,
    "has_hipaa_vocab": $HAS_HIPAA_VOCAB,
    "initial_alert_count": $INITIAL_ALERT_COUNT,
    "current_alert_count": $CURRENT_ALERT_COUNT,
    "new_alert_count": $NEW_ALERT_COUNT,
    "alert_created": $ALERT_CREATED,
    "phi_alert_found": $PHI_ALERT_FOUND,
    "log_retention_days": $LOG_RETENTION_DAYS,
    "retention_set": $RETENTION_SET,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Report exists: $REPORT_EXISTS (size=$REPORT_SIZE, hipaa_vocab=$HAS_HIPAA_VOCAB)"
echo "Alert created: $ALERT_CREATED (phi_found=$PHI_ALERT_FOUND, new=$NEW_ALERT_COUNT)"
echo "Log retention: $LOG_RETENTION_DAYS days (set=$RETENTION_SET)"
echo "=== Export Complete ==="
