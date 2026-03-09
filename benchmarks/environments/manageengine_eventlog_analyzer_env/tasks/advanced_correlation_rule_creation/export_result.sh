#!/bin/bash
# Export script for advanced_correlation_rule_creation

echo "=== Exporting advanced_correlation_rule_creation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

take_screenshot /tmp/advanced_correlation_rule_end.png

# --- Baseline ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count_corr 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_CORR_COUNT=$(cat /tmp/initial_corr_count 2>/dev/null | tr -d ' \n' || echo "0")
echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0
echo "$INITIAL_CORR_COUNT" | grep -qE '^[0-9]+$' || INITIAL_CORR_COUNT=0

# --- Check timeline file ---
TIMELINE_FILE="/home/ga/Desktop/attack_timeline.txt"
TIMELINE_EXISTS="false"
TIMELINE_SIZE=0
TIMELINE_MTIME=0
HAS_ATTACKER_IP="false"
HAS_SYSADMIN="false"
HAS_ESCALATION="false"
HAS_STAGES="false"

if [ -f "$TIMELINE_FILE" ]; then
    TIMELINE_EXISTS="true"
    TIMELINE_SIZE=$(wc -c < "$TIMELINE_FILE" 2>/dev/null || echo "0")
    TIMELINE_MTIME=$(stat -c %Y "$TIMELINE_FILE" 2>/dev/null || echo "0")

    if grep -q "203.0.113.42" "$TIMELINE_FILE" 2>/dev/null; then
        HAS_ATTACKER_IP="true"
    fi
    if grep -qi "sysadmin" "$TIMELINE_FILE" 2>/dev/null; then
        HAS_SYSADMIN="true"
    fi
    if grep -qiE "escalat|sudo|privilege|root|su " "$TIMELINE_FILE" 2>/dev/null; then
        HAS_ESCALATION="true"
    fi
    # Check for multi-stage documentation
    if grep -qiE "stage|phase|step|first|then|finally|initial|subsequent|follow" "$TIMELINE_FILE" 2>/dev/null; then
        HAS_STAGES="true"
    fi
fi

# --- Count current alerts ---
CURRENT_ALERT_COUNT=0
PRIV_ESC_ALERT_FOUND="false"
ALERT_TABLES_FILE="/tmp/alert_table_names_corr"
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
    # Check for privilege escalation alert
    for COL in alertname alert_name name rulename rule_name title; do
        PE_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $COL ILIKE '%privilege%' OR $COL ILIKE '%escalat%' OR $COL ILIKE '%sudo%'" 2>/dev/null | tr -d ' ')
        if echo "$PE_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            PRIV_ESC_ALERT_FOUND="true"
            break 2
        fi
    done
done

NEW_ALERT_COUNT=$((CURRENT_ALERT_COUNT - INITIAL_ALERT_COUNT))
ALERT_CREATED="false"
if [ "$NEW_ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_CREATED="true"
fi

# --- Count current correlation rules ---
CURRENT_CORR_COUNT=0
CORR_RULE_FOUND="false"
CORR_TABLES_FILE="/tmp/corr_table_names"
CORR_TABLES=""
if [ -f "$CORR_TABLES_FILE" ]; then
    CORR_TABLES=$(cat "$CORR_TABLES_FILE")
else
    CORR_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%corr%' OR tablename ILIKE '%rule%')" 2>/dev/null)
fi

for TABLE in $CORR_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        CURRENT_CORR_COUNT=$((CURRENT_CORR_COUNT + COUNT))
    fi
    # Check for multi-stage rule by name
    for COL in rulename rule_name name title description; do
        RULE_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $COL ILIKE '%brute%' OR $COL ILIKE '%multi%' OR $COL ILIKE '%compromise%' OR $COL ILIKE '%stage%'" 2>/dev/null | tr -d ' ')
        if echo "$RULE_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            CORR_RULE_FOUND="true"
            break 2
        fi
    done
done

NEW_CORR_COUNT=$((CURRENT_CORR_COUNT - INITIAL_CORR_COUNT))
CORR_CREATED="false"
if [ "$NEW_CORR_COUNT" -gt 0 ] 2>/dev/null; then
    CORR_CREATED="true"
fi

# Write result JSON
cat > /tmp/advanced_correlation_result.json << EOF
{
    "timeline_exists": $TIMELINE_EXISTS,
    "timeline_size": $TIMELINE_SIZE,
    "timeline_mtime": $TIMELINE_MTIME,
    "task_start": $TASK_START,
    "has_attacker_ip": $HAS_ATTACKER_IP,
    "has_sysadmin": $HAS_SYSADMIN,
    "has_escalation": $HAS_ESCALATION,
    "has_stages": $HAS_STAGES,
    "initial_alert_count": $INITIAL_ALERT_COUNT,
    "current_alert_count": $CURRENT_ALERT_COUNT,
    "new_alert_count": $NEW_ALERT_COUNT,
    "alert_created": $ALERT_CREATED,
    "priv_esc_alert_found": $PRIV_ESC_ALERT_FOUND,
    "initial_corr_count": $INITIAL_CORR_COUNT,
    "current_corr_count": $CURRENT_CORR_COUNT,
    "new_corr_count": $NEW_CORR_COUNT,
    "corr_created": $CORR_CREATED,
    "corr_rule_found": $CORR_RULE_FOUND,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Timeline: $TIMELINE_EXISTS (size=$TIMELINE_SIZE, ip=$HAS_ATTACKER_IP, sysadmin=$HAS_SYSADMIN)"
echo "Alert created: $ALERT_CREATED (priv_esc=$PRIV_ESC_ALERT_FOUND, new=$NEW_ALERT_COUNT)"
echo "Correlation rule: $CORR_CREATED (found=$CORR_RULE_FOUND, new=$NEW_CORR_COUNT)"
echo "=== Export Complete ==="
