#!/bin/bash
# export_result.sh — Broadcast Device Template Creation
# Collects device template data via API and DB, then writes /tmp/broadcast_template_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/broadcast_template_result.json"
TMP_TEMPLATES_API="/tmp/_templates_api.json"
TMP_TEMPLATES_DB="/tmp/_templates_db.txt"

echo "[export] === Exporting Broadcast Device Template Task ==="

# ------------------------------------------------------------
# Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_final.png" || true

# ------------------------------------------------------------
# 1. Obtain API key
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
# 2. Fetch device templates via API
# ------------------------------------------------------------
echo "[export] Fetching templates via API..."
TEMPLATES_FETCHED=0

for endpoint in \
    "/api/json/deviceTemplate/listTemplates" \
    "/api/json/template/list" \
    "/api/json/deviceTemplates"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_TEMPLATES_API"
        TEMPLATES_FETCHED=1
        echo "[export] Template list fetched from $endpoint"
        break
    fi
done

if [ "$TEMPLATES_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_TEMPLATES_API"
    echo "[export] WARNING: Could not fetch template list from any endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for template and sysoid tables
# ------------------------------------------------------------
echo "[export] Querying DB for template data..."

# Discover template-related table names
ALL_TEMPLATE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%template%' OR tablename ILIKE '%sysoid%' OR tablename ILIKE '%vendor%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
echo "[export] Template/SysOID tables: $ALL_TEMPLATE_TABLES"

{
    echo "=== DB TEMPLATE DUMP ==="
    for tbl in $ALL_TEMPLATE_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        # We limit to 500 rows to prevent massive files, but order by an ID descending if possible 
        # to catch newly created templates, or just dump all since template tables are generally < 2000 rows
        opmanager_query_headers "SELECT * FROM \"${tbl}\" ORDER BY 1 DESC LIMIT 1000;" 2>/dev/null || true
    done
} > "$TMP_TEMPLATES_DB" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)
APP_RUNNING=$(pgrep -f "java.*OpManager" > /dev/null && echo "true" || echo "false")

python3 << PYEOF
import json, sys, os

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

templates_api = load_json("${TMP_TEMPLATES_API}")
templates_db_raw = load_text("${TMP_TEMPLATES_DB}")

result = {
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "app_was_running": ${APP_RUNNING},
    "templates_api": templates_api,
    "templates_db_raw": templates_db_raw,
    "screenshot_path": "/tmp/task_final.png"
}

tmp_out = "/tmp/broadcast_template_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final location safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/broadcast_template_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/broadcast_template_result_tmp.json" "$RESULT_FILE"
fi

chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "[export] Result written to $RESULT_FILE"
rm -f "$TMP_TEMPLATES_DB" "$TMP_TEMPLATES_API" "/tmp/broadcast_template_result_tmp.json" || true
echo "[export] === Export Complete ==="