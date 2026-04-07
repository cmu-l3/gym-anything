#!/bin/bash
# Export script for insider_threat_investigation_and_response
# Captures: report file state, evidence PDF state, incident count delta, alert count delta

echo "=== Exporting insider_threat_investigation_and_response Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || \
        DISPLAY=:1 scrot "$output_file" 2>/dev/null || true
    }
fi

ELA_PSQL="/opt/ManageEngine/EventLog/pgsql/bin/psql"
ela_db_query() {
    "$ELA_PSQL" -h localhost -p 33335 -U eventloganalyzer -d eventlog -t -A -c "$1" 2>/dev/null
}

# Take final screenshot
take_screenshot /tmp/insider_threat_investigation_end.png

# --- Read baselines ---
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_ALERT_COUNT=$(cat /tmp/initial_alert_count_insider 2>/dev/null | tr -d ' \n' || echo "0")
INITIAL_INCIDENT_COUNT=$(cat /tmp/initial_incident_count_insider 2>/dev/null | tr -d ' \n' || echo "0")

echo "$TASK_START" | grep -qE '^[0-9]+$' || TASK_START=0
echo "$INITIAL_ALERT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_ALERT_COUNT=0
echo "$INITIAL_INCIDENT_COUNT" | grep -qE '^[0-9]+$' || INITIAL_INCIDENT_COUNT=0

# --- Check incident report file (~/Desktop/insider_threat_report.txt) ---
REPORT_FILE="/home/ga/Desktop/insider_threat_report.txt"
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_MTIME=0
HAS_ATTACKER_IP="false"
HAS_PRIMARY_ACCOUNT="false"
HAS_SECONDARY_ACCOUNT="false"
HAS_ESCALATION="false"
HAS_REMEDIATION="false"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(wc -c < "$REPORT_FILE" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")

    if grep -q "10.55.3.88" "$REPORT_FILE" 2>/dev/null; then
        HAS_ATTACKER_IP="true"
    fi
    if grep -qi "svc_dataops" "$REPORT_FILE" 2>/dev/null; then
        HAS_PRIMARY_ACCOUNT="true"
    fi
    if grep -qi "svc_reporting" "$REPORT_FILE" 2>/dev/null; then
        HAS_SECONDARY_ACCOUNT="true"
    fi
    if grep -qiE "sudo|privilege|escalat|root" "$REPORT_FILE" 2>/dev/null; then
        HAS_ESCALATION="true"
    fi
    if grep -qiE "remediat|recommend|mitigat|block|firewall|lockout|disable|password|reset|revoke" "$REPORT_FILE" 2>/dev/null; then
        HAS_REMEDIATION="true"
    fi
fi

# --- Check evidence PDF (~/Desktop/insider_threat_evidence.pdf) ---
EVIDENCE_FILE="/home/ga/Desktop/insider_threat_evidence.pdf"
EVIDENCE_EXISTS="false"
EVIDENCE_SIZE=0
EVIDENCE_MTIME=0
EVIDENCE_VALID_PDF="false"

if [ -f "$EVIDENCE_FILE" ]; then
    EVIDENCE_EXISTS="true"
    EVIDENCE_SIZE=$(stat -c %s "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    EVIDENCE_MTIME=$(stat -c %Y "$EVIDENCE_FILE" 2>/dev/null || echo "0")
    # Check for valid PDF header
    if head -c 4 "$EVIDENCE_FILE" 2>/dev/null | grep -q "%PDF"; then
        EVIDENCE_VALID_PDF="true"
    fi
    # Copy to /tmp for verifier access
    cp "$EVIDENCE_FILE" /tmp/insider_threat_evidence.pdf 2>/dev/null || true
    chmod 666 /tmp/insider_threat_evidence.pdf 2>/dev/null || true
fi

# --- Count current alerts and check for brute-force alert ---
CURRENT_ALERT_COUNT=0
BRUTE_FORCE_ALERT_FOUND="false"

ALERT_TABLES_FILE="/tmp/alert_table_names_insider"
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
    # Look for brute-force / service-account related alert name
    for COL in alertname alert_name name rulename rule_name title; do
        BF_CHECK=$(ela_db_query "SELECT COUNT(*) FROM \"$TABLE\" WHERE $COL ILIKE '%brute%' OR $COL ILIKE '%service account%' OR $COL ILIKE '%svc_%'" 2>/dev/null | tr -d ' ')
        if echo "$BF_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            BRUTE_FORCE_ALERT_FOUND="true"
            break 2
        fi
    done
done

NEW_ALERT_COUNT=$((CURRENT_ALERT_COUNT - INITIAL_ALERT_COUNT))
ALERT_CREATED="false"
if [ "$NEW_ALERT_COUNT" -gt 0 ] 2>/dev/null; then
    ALERT_CREATED="true"
fi

# --- Check current incident count and look for matching incident ---
CURRENT_INCIDENT_COUNT=0
INCIDENT_FOUND="false"
INCIDENT_HAS_IP="false"
INCIDENT_HAS_SECONDARY="false"

if type ela_api_call &>/dev/null; then
    INCIDENTS_RAW=$(ela_api_call "/event/api/v2/incidents" "GET" 2>/dev/null)
    CURRENT_INCIDENT_COUNT=$(echo "$INCIDENTS_RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    incidents = data.get('incidents', data.get('data', []))
    print(len(incidents))
except:
    print('0')
" 2>/dev/null || echo "0")

    # Search for matching incident
    INCIDENT_MATCH=$(echo "$INCIDENTS_RAW" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    incidents = data.get('incidents', data.get('data', []))
    for inc in incidents:
        title = inc.get('title', inc.get('subject', '')).lower()
        if 'insider' in title or 'service account' in title or 'compromise' in title:
            desc = json.dumps(inc).lower()
            has_ip = '10.55.3.88' in desc
            has_secondary = 'svc_reporting' in desc
            print(json.dumps({'found': True, 'has_ip': has_ip, 'has_secondary': has_secondary}))
            sys.exit(0)
    print(json.dumps({'found': False, 'has_ip': False, 'has_secondary': False}))
except:
    print(json.dumps({'found': False, 'has_ip': False, 'has_secondary': False}))
" 2>/dev/null)

    if echo "$INCIDENT_MATCH" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('found') else 1)" 2>/dev/null; then
        INCIDENT_FOUND="true"
        if echo "$INCIDENT_MATCH" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('has_ip') else 1)" 2>/dev/null; then
            INCIDENT_HAS_IP="true"
        fi
        if echo "$INCIDENT_MATCH" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('has_secondary') else 1)" 2>/dev/null; then
            INCIDENT_HAS_SECONDARY="true"
        fi
    fi
fi

# DB fallback: check for incident in DB tables
if [ "$INCIDENT_FOUND" = "false" ]; then
    for TNAME in helpdesk_ticket arc_incident; do
        DB_CHECK=$(ela_db_query "SELECT COUNT(*) FROM $TNAME WHERE title ILIKE '%insider%' OR title ILIKE '%service account%' OR title ILIKE '%compromise%'" 2>/dev/null | tr -d ' ')
        if echo "$DB_CHECK" | grep -qE '^[1-9][0-9]*$'; then
            INCIDENT_FOUND="true"
            break
        fi
    done
fi

NEW_INCIDENT_COUNT=$((CURRENT_INCIDENT_COUNT - INITIAL_INCIDENT_COUNT))

# --- Write result JSON ---
cat > /tmp/insider_threat_investigation_result.json << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_size": $REPORT_SIZE,
    "report_mtime": $REPORT_MTIME,
    "has_attacker_ip": $HAS_ATTACKER_IP,
    "has_primary_account": $HAS_PRIMARY_ACCOUNT,
    "has_secondary_account": $HAS_SECONDARY_ACCOUNT,
    "has_escalation": $HAS_ESCALATION,
    "has_remediation": $HAS_REMEDIATION,
    "evidence_exists": $EVIDENCE_EXISTS,
    "evidence_size": $EVIDENCE_SIZE,
    "evidence_mtime": $EVIDENCE_MTIME,
    "evidence_valid_pdf": $EVIDENCE_VALID_PDF,
    "initial_alert_count": $INITIAL_ALERT_COUNT,
    "current_alert_count": $CURRENT_ALERT_COUNT,
    "new_alert_count": $NEW_ALERT_COUNT,
    "alert_created": $ALERT_CREATED,
    "brute_force_alert_found": $BRUTE_FORCE_ALERT_FOUND,
    "initial_incident_count": $INITIAL_INCIDENT_COUNT,
    "current_incident_count": $CURRENT_INCIDENT_COUNT,
    "new_incident_count": $NEW_INCIDENT_COUNT,
    "incident_found": $INCIDENT_FOUND,
    "incident_has_ip": $INCIDENT_HAS_IP,
    "incident_has_secondary": $INCIDENT_HAS_SECONDARY,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Report: exists=$REPORT_EXISTS size=$REPORT_SIZE ip=$HAS_ATTACKER_IP primary=$HAS_PRIMARY_ACCOUNT secondary=$HAS_SECONDARY_ACCOUNT escalation=$HAS_ESCALATION"
echo "Evidence PDF: exists=$EVIDENCE_EXISTS size=$EVIDENCE_SIZE valid=$EVIDENCE_VALID_PDF"
echo "Alert: created=$ALERT_CREATED brute_force=$BRUTE_FORCE_ALERT_FOUND new=$NEW_ALERT_COUNT"
echo "Incident: found=$INCIDENT_FOUND has_ip=$INCIDENT_HAS_IP has_secondary=$INCIDENT_HAS_SECONDARY new=$NEW_INCIDENT_COUNT"
echo "=== Export Complete ==="
