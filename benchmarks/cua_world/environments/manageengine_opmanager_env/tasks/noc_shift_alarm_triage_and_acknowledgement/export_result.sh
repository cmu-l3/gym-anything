#!/bin/bash
# export_result.sh — NOC Shift Alarm Triage and Acknowledgment
# Extracts alarm states, event history, and annotations from OpManager API and DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/alarm_triage_result.json"

echo "[export] === Exporting Alarm Triage Results ==="

# ------------------------------------------------------------
# Take Final Screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_final.png" || true

# ------------------------------------------------------------
# Obtain API key
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST \
        "http://localhost:8060/apiv2/login" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "
import json, sys
try:
    d = json.loads(sys.argv[1])
    print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))
except Exception:
    pass
" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

# ------------------------------------------------------------
# 1. Fetch Alarms from API
# ------------------------------------------------------------
echo "[export] Fetching active alarms via API..."
API_ALARMS=$(curl -sf "http://localhost:8060/api/json/alarm/getAlarms?apiKey=${API_KEY}" 2>/dev/null || echo '{}')
echo "$API_ALARMS" > /tmp/_api_alarms.json

# ------------------------------------------------------------
# 2. Query DB for Alert, Event, and Annotation tables
# ------------------------------------------------------------
echo "[export] Querying DB for alarm history and notes..."

# Dump active alerts
opmanager_query_headers "SELECT * FROM Alert LIMIT 500;" 2>/dev/null > /tmp/_db_alerts.txt || echo "" > /tmp/_db_alerts.txt

# Dump recent events (to catch "cleared" audit logs)
opmanager_query_headers "SELECT * FROM Event ORDER BY eventid DESC LIMIT 1000;" 2>/dev/null > /tmp/_db_events.txt || echo "" > /tmp/_db_events.txt

# Discover and dump annotation/notes tables
ANNOTATION_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%annotat%' LIMIT 1;" 2>/dev/null | tr -d ' \t' || true)
if [ -n "$ANNOTATION_TABLE" ]; then
    opmanager_query_headers "SELECT * FROM \"${ANNOTATION_TABLE}\" LIMIT 500;" 2>/dev/null > /tmp/_db_annotations.txt || echo "" > /tmp/_db_annotations.txt
else
    echo "" > /tmp/_db_annotations.txt
fi

NOTES_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%notes%' LIMIT 1;" 2>/dev/null | tr -d ' \t' || true)
if [ -n "$NOTES_TABLE" ]; then
    opmanager_query_headers "SELECT * FROM \"${NOTES_TABLE}\" LIMIT 500;" 2>/dev/null > /tmp/_db_notes.txt || echo "" > /tmp/_db_notes.txt
else
    echo "" > /tmp/_db_notes.txt
fi

# ------------------------------------------------------------
# 3. Assemble JSON Payload
# ------------------------------------------------------------
echo "[export] Assembling final JSON..."

python3 << 'PYEOF'
import json, os

def read_file(path):
    try:
        with open(path, 'r') as f:
            return f.read()
    except Exception:
        return ""

api_alarms = {}
try:
    with open('/tmp/_api_alarms.json', 'r') as f:
        api_alarms = json.load(f)
except Exception:
    pass

result = {
    "api_alarms": api_alarms,
    "db_alerts_raw": read_file('/tmp/_db_alerts.txt'),
    "db_events_raw": read_file('/tmp/_db_events.txt'),
    "db_annotations_raw": read_file('/tmp/_db_annotations.txt'),
    "db_notes_raw": read_file('/tmp/_db_notes.txt'),
    "export_timestamp": os.popen('date -Iseconds').read().strip()
}

with open('/tmp/alarm_triage_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final destination safely
mv /tmp/alarm_triage_result_tmp.json "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true

# Cleanup
rm -f /tmp/_api_alarms.json /tmp/_db_alerts.txt /tmp/_db_events.txt /tmp/_db_annotations.txt /tmp/_db_notes.txt

echo "[export] === Export Complete ==="