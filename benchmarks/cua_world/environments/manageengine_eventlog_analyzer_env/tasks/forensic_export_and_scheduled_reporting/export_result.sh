#!/bin/bash
# Export script for forensic_export_and_scheduled_reporting

echo "=== Exporting forensic_export_and_scheduled_reporting Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

take_screenshot /tmp/forensic_export_end.png

# --- Baseline ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count_forensic 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_REPORT_COUNT=$(cat /tmp/initial_report_count_forensic 2>/dev/null | tr -d ' \n' || echo "0")
echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0
echo "$INITIAL_REPORT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_REPORT_COUNT=0

# --- Check CSV export file ---
CSV_FILE="/home/ga/Desktop/root_activity_export.csv"
CSV_EXISTS="false"
CSV_SIZE=0
CSV_MTIME=0

if [ -f "$CSV_FILE" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(wc -c < "$CSV_FILE" 2>/dev/null || echo "0")
    CSV_MTIME=$(stat -c %Y "$CSV_FILE" 2>/dev/null || echo "0")
fi

# --- Check scheduled report in DB ---
CURRENT_REPORT_COUNT=0
DAILY_REPORT_FOUND="false"
SOC_REPORT_FOUND="false"

REPORT_TABLES_FILE="/tmp/report_table_names_forensic"
REPORT_TABLES=""
if [ -f "$REPORT_TABLES_FILE" ]; then
    REPORT_TABLES=$(cat "$REPORT_TABLES_FILE")
else
    REPORT_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%report%' OR tablename ILIKE '%schedule%')" 2>/dev/null)
fi

for TABLE in $REPORT_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        CURRENT_REPORT_COUNT=$((CURRENT_REPORT_COUNT + COUNT))
    fi
    # Look for daily scheduled report
    for FREQ_COL in frequency schedulefrequency schedule_frequency period; do
        DAILY_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $FREQ_COL ILIKE '%daily%' OR $FREQ_COL = '1' OR $FREQ_COL ILIKE '%day%'" 2>/dev/null | tr -d ' ')
        if echo "$DAILY_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            DAILY_REPORT_FOUND="true"
            break
        fi
    done
    # Look for report named SOC or Security Summary
    for NAME_COL in reportname report_name name title; do
        SOC_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $NAME_COL ILIKE '%soc%' OR $NAME_COL ILIKE '%security%' OR $NAME_COL ILIKE '%summary%' OR $NAME_COL ILIKE '%daily%'" 2>/dev/null | tr -d ' ')
        if echo "$SOC_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            SOC_REPORT_FOUND="true"
            break
        fi
    done
done

NEW_REPORT_COUNT=$((CURRENT_REPORT_COUNT - INITIAL_REPORT_COUNT))
REPORT_CREATED="false"
if [ "$NEW_REPORT_COUNT" -gt 0 ] 2>/dev/null; then
    REPORT_CREATED="true"
fi

# --- Check alert in DB ---
CURRENT_ALERT_COUNT=0
ROOT_ALERT_FOUND="false"

ALERT_TABLES_FILE="/tmp/alert_table_names_forensic"
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
    for COL in alertname alert_name name rulename rule_name title; do
        ROOT_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $COL ILIKE '%root%' OR $COL ILIKE '%privileged%' OR $COL ILIKE '%access monitor%'" 2>/dev/null | tr -d ' ')
        if echo "$ROOT_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            ROOT_ALERT_FOUND="true"
            break 2
        fi
    done
done

NEW_ALERT_COUNT=$((CURRENT_ALERT_COUNT - INITIAL_ALERT_COUNT))
ALERT_CREATED="false"
if [ "$NEW_ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_CREATED="true"
fi

# --- Check log archival/retention in DB ---
ARCHIVE_FOUND="false"
ARCHIVE_DAYS=0

for TABLE_QUERY in \
    "SELECT retentionperiod FROM archiveconfig LIMIT 1" \
    "SELECT value FROM globalconfig WHERE name ILIKE '%archive%' OR name ILIKE '%retention%' LIMIT 1" \
    "SELECT configvalue FROM logarchive LIMIT 1" \
    "SELECT archiveperiod FROM logsettings LIMIT 1"; do
    RESULT=$(ela_db_query "$TABLE_QUERY" 2>/dev/null | tr -d ' ')
    if echo "$RESULT" | grep -qE '^[0-9]+$'; then
        ARCHIVE_DAYS=$RESULT
        if [ "$ARCHIVE_DAYS" -ge 730 ] 2>/dev/null; then
            ARCHIVE_FOUND="true"
        fi
        break
    fi
done

# Write result JSON
cat > /tmp/forensic_export_result.json << EOF
{
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "initial_alert_count": $INITIAL_ALERT_COUNT,
    "current_alert_count": $CURRENT_ALERT_COUNT,
    "new_alert_count": $NEW_ALERT_COUNT,
    "alert_created": $ALERT_CREATED,
    "root_alert_found": $ROOT_ALERT_FOUND,
    "initial_report_count": $INITIAL_REPORT_COUNT,
    "current_report_count": $CURRENT_REPORT_COUNT,
    "new_report_count": $NEW_REPORT_COUNT,
    "report_created": $REPORT_CREATED,
    "daily_report_found": $DAILY_REPORT_FOUND,
    "soc_report_found": $SOC_REPORT_FOUND,
    "archive_found": $ARCHIVE_FOUND,
    "archive_days": $ARCHIVE_DAYS,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "CSV: exists=$CSV_EXISTS size=$CSV_SIZE mtime=$CSV_MTIME"
echo "Alert: created=$ALERT_CREATED root_found=$ROOT_ALERT_FOUND new=$NEW_ALERT_COUNT"
echo "Report: created=$REPORT_CREATED daily=$DAILY_REPORT_FOUND soc=$SOC_REPORT_FOUND new=$NEW_REPORT_COUNT"
echo "Archive: found=$ARCHIVE_FOUND days=$ARCHIVE_DAYS"
echo "=== Export Complete ==="
