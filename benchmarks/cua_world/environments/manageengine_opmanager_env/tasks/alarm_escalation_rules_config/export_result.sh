#!/bin/bash
# export_result.sh — Alarm Escalation Rules Configuration
# Collects rule data from the DB and API to verify task success.

set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "[export] === Exporting Alarm Escalation Rules Results ==="

RESULT_FILE="/tmp/alarm_escalation_result.json"
TMP_API="/tmp/_escalation_api.json"
TMP_DB="/tmp/_escalation_db.txt"

# ------------------------------------------------------------
# 1. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_final.png" || true

# ------------------------------------------------------------
# 2. Obtain API key
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 3. Fetch Escalation Rules via API
# ------------------------------------------------------------
echo "[export] Fetching alarm escalation rules via API..."
API_FETCHED=0

for endpoint in \
    "/api/json/alarm/escalation/listRules" \
    "/api/json/v2/alarms/escalation" \
    "/api/json/notification/listProfiles" \
    "/api/json/escalation/listRules"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API"
        API_FETCHED=1
        echo "[export] Rules fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API"
    echo "[export] WARNING: Could not fetch rules via any standard API endpoint." >&2
fi

# ------------------------------------------------------------
# 4. Query Database for Escalation / Notification tables
# ------------------------------------------------------------
echo "[export] Querying DB for Escalation and Notification tables..."

# Find candidate tables
CANDIDATE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%escalat%' OR tablename ILIKE '%rule%' OR tablename ILIKE '%notif%' OR tablename ILIKE '%profile%' OR tablename ILIKE '%action%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered candidate tables: $CANDIDATE_TABLES"

{
    echo "=== ALARM ESCALATION DB DUMP ==="
    if [ -n "$CANDIDATE_TABLES" ]; then
        for tbl in $CANDIDATE_TABLES; do
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        done
    else
        echo "NO CANDIDATE TABLES FOUND"
    fi
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 5. Assemble JSON Result
# ------------------------------------------------------------
echo "[export] Assembling JSON result..."

python3 << 'PYEOF'
import json, os

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

api_data = load_json("/tmp/_escalation_api.json")
db_raw = load_text("/tmp/_escalation_db.txt")

result = {
    "api_data": api_data,
    "db_raw": db_raw,
    "timestamp": os.popen("date -Iseconds").read().strip()
}

out_tmp = "/tmp/_alarm_escalation_result_tmp.json"
with open(out_tmp, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move temp file to final destination safely
mv "/tmp/_alarm_escalation_result_tmp.json" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "[export] Result saved to $RESULT_FILE"
echo "[export] === Export Complete ==="