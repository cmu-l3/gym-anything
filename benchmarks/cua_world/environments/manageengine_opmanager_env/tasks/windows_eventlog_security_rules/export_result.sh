#!/bin/bash
# export_result.sh — Windows Event Log Security Rules
# Collects Event Log Rules from the API and DB,
# then writes /tmp/eventlog_rules_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/eventlog_rules_result.json"
TMP_API="/tmp/_eventlog_api.json"
TMP_DB="/tmp/_eventlog_db.txt"

# ------------------------------------------------------------
# Obtain API key
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
# 1. Fetch event log rules via API
# ------------------------------------------------------------
echo "[export] Fetching Event Log Rules via API..."
RULES_FETCHED=0

for endpoint in \
    "/api/json/eventlogrule/listRules" \
    "/api/json/admin/getEventLogRules" \
    "/api/json/eventlog/rules" \
    "/api/json/eventlogrule/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API"
        RULES_FETCHED=1
        echo "[export] Rules list fetched from $endpoint"
        break
    fi
done

if [ "$RULES_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API"
    echo "[export] WARNING: Could not fetch event log rules from any endpoint." >&2
fi

# ------------------------------------------------------------
# 2. Query DB for event log rule tables
# ------------------------------------------------------------
echo "[export] Querying DB for Event Log rule data..."

TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%eventlog%' OR tablename ILIKE '%winevent%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

if [ -z "$TABLES" ]; then
    # Fallback to general rules tables
    TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%rule%' ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
fi

{
    echo "=== DISCOVERED TABLES ==="
    echo "$TABLES"
    echo ""

    for tbl in $TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble JSON Result
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, sys

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

result = {
    "api_data": load_json("/tmp/_eventlog_api.json"),
    "db_raw": load_text("/tmp/_eventlog_db.txt")
}

tmp_out = "/tmp/eventlog_rules_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/eventlog_rules_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/eventlog_rules_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_API" "$TMP_DB" || true