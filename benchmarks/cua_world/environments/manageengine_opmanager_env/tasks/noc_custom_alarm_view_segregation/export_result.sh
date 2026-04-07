#!/bin/bash
# export_result.sh — NOC Custom Alarm View Segregation
# Collects custom alarm views via API and DB, then writes /tmp/alarm_view_result.json.

set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "[export] === Exporting Alarm View Results ==="

RESULT_FILE="/tmp/alarm_view_result.json"

# Capture final state for potential visual verification
take_screenshot "/tmp/task_final.png" || true

# 1. Obtain API key
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi
if [ -z "$API_KEY" ]; then
    echo "[export] API key not found; attempting login..." >&2
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

# 2. Fetch Alarm Views via API
echo "{}" > /tmp/_api_responses.json
if [ -n "$API_KEY" ]; then
    python3 -c "
import urllib.request, json, sys
api_key = sys.argv[1]
urls = [
    f'http://localhost:8060/api/json/alarm/getAlarmViews?apiKey={api_key}',
    f'http://localhost:8060/api/json/customview/getViews?apiKey={api_key}'
]
res = {}
for u in urls:
    try:
        req = urllib.request.Request(u)
        with urllib.request.urlopen(req, timeout=10) as r:
            res[u] = json.loads(r.read().decode())
    except Exception:
        pass
with open('/tmp/_api_responses.json', 'w') as f:
    json.dump(res, f)
" "$API_KEY"
    echo "[export] API responses fetched."
else
    echo "[export] WARNING: Could not obtain API key for API fetches."
fi

# 3. Query DB for Custom View Tables
DB_RAW="/tmp/_alarm_db.txt"
echo "=== DB ALARM VIEWS ===" > "$DB_RAW"

echo "[export] Querying DB for view-related tables..."
TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%view%' OR tablename ILIKE '%filter%' OR tablename ILIKE '%alarm%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

COUNT=0
for tbl in $TABLES; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -gt 25 ]; then break; fi
    echo "--- Table: $tbl ---" >> "$DB_RAW"
    opmanager_query_headers "SELECT * FROM \"$tbl\" LIMIT 200;" >> "$DB_RAW" 2>/dev/null || true
done
echo "[export] Database queries complete."

# 4. Assemble Results JSON
python3 << 'PYEOF'
import json

try:
    with open("/tmp/_api_responses.json", "r") as f:
        api_responses = json.load(f)
except Exception:
    api_responses = {}

try:
    with open("/tmp/_alarm_db.txt", "r") as f:
        db_raw = f.read()
except Exception:
    db_raw = ""

with open("/tmp/alarm_view_result.json", "w") as f:
    json.dump({"api_responses": api_responses, "db_raw": db_raw}, f)
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true
echo "[export] Result written to $RESULT_FILE"
echo "[export] === Export Complete ==="