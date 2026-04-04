#!/bin/bash
# Export script for siem_hardening_and_user_audit

echo "=== Exporting siem_hardening_and_user_audit Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

take_screenshot /tmp/siem_hardening_end.png

# --- Baseline ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_TECH_COUNT=$(cat /tmp/initial_tech_count 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count_hardening 2>/dev/null | tr -d ' \n' || echo "0")
echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_TECH_COUNT" | grep -qE '^[0-9]+$' || INITIAL_TECH_COUNT=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0

# --- Check hardening report file ---
REPORT_FILE="/home/ga/Desktop/hardening_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
REPORT_HAS_CONTRACTOR="false"
REPORT_HAS_NEW_ACCOUNT="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if grep -qi "contractor01" "$REPORT_FILE" 2>/dev/null; then
        REPORT_HAS_CONTRACTOR="true"
    fi
    if grep -qi "soc-analyst-02\|soc_analyst_02\|socanalyst02" "$REPORT_FILE" 2>/dev/null; then
        REPORT_HAS_NEW_ACCOUNT="true"
    fi
fi

# --- Check contractor01 role in DB ---
CONTRACTOR01_ROLE="unknown"
CONTRACTOR01_DOWNGRADED="false"

TECH_TABLES_FILE="/tmp/tech_table_names"
TECH_TABLES=""
if [ -f "$TECH_TABLES_FILE" ]; then
    TECH_TABLES=$(cat "$TECH_TABLES_FILE")
else
    TECH_TABLES=$(ela_db_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%tech%' OR tablename ILIKE '%user%')" 2>/dev/null)
fi

for TABLE in $TECH_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    # Try to find contractor01's role
    for USER_COL in username user_name login loginname; do
        for ROLE_COL in role rolename role_name usertype user_type; do
            ROLE_RESULT=$(ela_db_query "SELECT $ROLE_COL FROM \"$TABLE\" WHERE $USER_COL='contractor01'" 2>/dev/null | tr -d ' ' | head -1)
            if [ -n "$ROLE_RESULT" ] && [ "$ROLE_RESULT" != "" ]; then
                CONTRACTOR01_ROLE="$ROLE_RESULT"
                # Check if role was downgraded (not admin)
                if echo "$ROLE_RESULT" | grep -qiE "operator|reader|viewer|limited" 2>/dev/null; then
                    CONTRACTOR01_DOWNGRADED="true"
                fi
                break 2
            fi
        done
    done
    [ "$CONTRACTOR01_ROLE" != "unknown" ] && break
done

# Also check via API
COOKIE_JAR="/tmp/ela_export_cookies.txt"
rm -f "$COOKIE_JAR"
curl -s -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "j_username=admin&j_password=admin&Submit=Login" \
    "http://localhost:8095/event/j_security_check" -o /dev/null 2>/dev/null

CONTRACTOR01_API_ROLE=""
TECH_LIST=$(curl -s -b "$COOKIE_JAR" "http://localhost:8095/event/api/v1/technicians" 2>/dev/null)
if [ -n "$TECH_LIST" ]; then
    CONTRACTOR01_API_ROLE=$(echo "$TECH_LIST" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('technicians', data.get('data', []))
    for t in items:
        if t.get('username','') == 'contractor01':
            print(t.get('role', t.get('roleName', '')))
            break
except:
    pass
" 2>/dev/null)
fi
if echo "$CONTRACTOR01_API_ROLE" | grep -qiE "operator|reader|viewer|limited" 2>/dev/null; then
    CONTRACTOR01_DOWNGRADED="true"
fi

# --- Check soc-analyst-02 exists ---
SOC_ANALYST_CREATED="false"

for TABLE in $TECH_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    for USER_COL in username user_name login loginname; do
        SOC_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $USER_COL='soc-analyst-02' OR $USER_COL='soc_analyst_02'" 2>/dev/null | tr -d ' ')
        if echo "$SOC_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            SOC_ANALYST_CREATED="true"
            break 2
        fi
    done
done

# Check via API
SOC_API_EXISTS=$(echo "$TECH_LIST" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    items = data if isinstance(data, list) else data.get('technicians', data.get('data', []))
    for t in items:
        u = t.get('username','')
        if u in ['soc-analyst-02', 'soc_analyst_02']:
            print('true')
            break
except:
    pass
" 2>/dev/null)
if [ "$SOC_API_EXISTS" = "true" ]; then
    SOC_ANALYST_CREATED="true"
fi

# --- Count current technicians ---
CURRENT_TECH_COUNT=0
for TABLE in $TECH_TABLES; do
    TABLE=$(echo "$TABLE" | tr -d '|' | xargs 2>/dev/null)
    [ -z "$TABLE" ] && continue
    COUNT=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\"" 2>/dev/null | tr -d ' ')
    if echo "$COUNT" | grep -qE '^[0-9]+$'; then
        CURRENT_TECH_COUNT=$((CURRENT_TECH_COUNT + COUNT))
    fi
done
NEW_TECH_COUNT=$((CURRENT_TECH_COUNT - INITIAL_TECH_COUNT))

# Write result JSON
# Escape contractor01 role for JSON
CONTRACTOR01_ROLE_ESC=$(echo "$CONTRACTOR01_ROLE" | sed 's/"/\\"/g' | tr -d '\n')

cat > /tmp/siem_hardening_result.json << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "task_start": $TASK_START,
    "report_has_contractor": $REPORT_HAS_CONTRACTOR,
    "report_has_new_account": $REPORT_HAS_NEW_ACCOUNT,
    "contractor01_role": "$CONTRACTOR01_ROLE_ESC",
    "contractor01_downgraded": $CONTRACTOR01_DOWNGRADED,
    "soc_analyst_created": $SOC_ANALYST_CREATED,
    "initial_tech_count": $INITIAL_TECH_COUNT,
    "current_tech_count": $CURRENT_TECH_COUNT,
    "new_tech_count": $NEW_TECH_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Report: $REPORT_EXISTS size=$REPORT_SIZE contractor=$REPORT_HAS_CONTRACTOR newacct=$REPORT_HAS_NEW_ACCOUNT"
echo "contractor01 role: $CONTRACTOR01_ROLE (downgraded=$CONTRACTOR01_DOWNGRADED)"
echo "soc-analyst-02 created: $SOC_ANALYST_CREATED"
echo "Tech count: initial=$INITIAL_TECH_COUNT current=$CURRENT_TECH_COUNT new=$NEW_TECH_COUNT"
echo "=== Export Complete ==="
