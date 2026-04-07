#!/bin/bash
# export_result.sh — External SaaS SSL Certificate Monitoring
# Queries the OpManager DB and API for SSL monitors, then writes JSON result.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/ssl_monitor_result.json"
TMP_SSL_DB="/tmp/_ssl_db.txt"
TMP_SSL_API="/tmp/_ssl_api.json"

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
# 1. Fetch SSL monitors from API
# ------------------------------------------------------------
echo "[export] Querying API for SSL monitors..."
SSL_API_RESP=$(opmanager_api_get "/api/json/sslcertificate/list" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/sslcertificate/list?apiKey=${API_KEY}" 2>/dev/null || \
    echo '{}')
echo "$SSL_API_RESP" > "$TMP_SSL_API"

# ------------------------------------------------------------
# 2. Query DB for SSL monitors (dynamic table discovery)
# ------------------------------------------------------------
echo "[export] Querying DB for SSL monitors..."
SSL_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%ssl%' OR tablename ILIKE '%cert%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== SSL TABLE SEARCH RESULTS ==="
    echo "Tables found: $SSL_TABLES"
    echo ""
    for tbl in $SSL_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        echo ""
    done
} > "$TMP_SSL_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."
python3 << 'PYEOF'
import json

def load_text(path):
    try:
        with open(path) as f:
            return f.read()
    except Exception:
        return ""

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return {}

ssl_db = load_text("/tmp/_ssl_db.txt")
ssl_api = load_json("/tmp/_ssl_api.json")

result = {
    "ssl_db_raw": ssl_db,
    "ssl_api": ssl_api
}

with open("/tmp/ssl_monitor_result_tmp.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Move to final location safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/ssl_monitor_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/ssl_monitor_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo mv "/tmp/ssl_monitor_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_SSL_DB" "$TMP_SSL_API" || true