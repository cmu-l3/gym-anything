#!/bin/bash
# export_result.sh — Proprietary Telemetry Script Template Setup
# Collects script templates from the API and DB, then writes /tmp/proprietary_telemetry_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/proprietary_telemetry_result.json"
TMP_TEMPLATES_API="/tmp/_script_templates_api.json"
TMP_SCRIPT_DB="/tmp/_script_db.txt"

# Take final screenshot
take_screenshot "/tmp/proprietary_telemetry_final_screenshot.png" || true

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
# 1. Fetch script templates from API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching script templates from API..."
TEMPLATES_FETCHED=0

for endpoint in \
    "/api/json/admin/getScriptTemplates" \
    "/api/json/admin/scriptTemplates" \
    "/api/json/script/getScriptTemplates" \
    "/api/json/scriptmonitor/list" \
    "/api/json/script/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_TEMPLATES_API"
        TEMPLATES_FETCHED=1
        echo "[export] Script templates fetched from $endpoint"
        break
    fi
done

if [ "$TEMPLATES_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_TEMPLATES_API"
    echo "[export] WARNING: Could not fetch script templates from any API endpoint." >&2
fi

# ------------------------------------------------------------
# 2. Query DB for script templates
# ------------------------------------------------------------
echo "[export] Querying DB for script template tables..."

ALL_SCRIPT_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%script%' OR tablename ILIKE '%template%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] All script/template-related tables: $ALL_SCRIPT_TABLES"

{
    echo "=== SCRIPT TEMPLATE TABLE SEARCH RESULTS ==="
    echo "Tables found: $ALL_SCRIPT_TABLES"
    echo ""

    # Dump each discovered table
    for tbl in $ALL_SCRIPT_TABLES; do
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_SCRIPT_DB" 2>&1

# ------------------------------------------------------------
# 3. Combine into result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
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

templates_api = load_json("/tmp/_script_templates_api.json")
script_db_raw = load_text("/tmp/_script_db.txt")

result = {
    "script_templates_api": templates_api,
    "script_db_raw": script_db_raw
}

tmp_out = "/tmp/proprietary_telemetry_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/proprietary_telemetry_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/proprietary_telemetry_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_TEMPLATES_API" "$TMP_SCRIPT_DB" "/tmp/proprietary_telemetry_result_tmp.json" || true