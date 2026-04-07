#!/bin/bash
# export_result.sh — Device Snapshot Quick Links Integration
# Collects quick link configuration data from the DB and API, then writes /tmp/quick_links_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/quick_links_result.json"
TMP_DB_RAW="/tmp/_ql_db_raw.txt"
TMP_API_RAW="/tmp/_ql_api_raw.json"

echo "[export] === Exporting Quick Links Result ==="

# Take final screenshot
take_screenshot "/tmp/quick_links_final_screenshot.png" || true

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
# 2. Query Database for Quick Links
# ------------------------------------------------------------
echo "[export] Querying PostgreSQL DB for quick link tables..."

# Search for tables that might contain quick links
CANDIDATE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%quick%link%' OR tablename ILIKE '%custom%link%' OR tablename ILIKE '%device%link%') ORDER BY tablename;" 2>/dev/null | tr -d ' \t' || true)

if [ -z "$CANDIDATE_TABLES" ]; then
    # Broader fallback search if specific names aren't found
    CANDIDATE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%link%' ORDER BY tablename;" 2>/dev/null | tr -d ' \t' || true)
fi

echo "[export] Discovered candidate tables: $CANDIDATE_TABLES"

{
    echo "=== QUICK LINKS DATABASE EXTRACT ==="
    if [ -n "$CANDIDATE_TABLES" ]; then
        for tbl in $CANDIDATE_TABLES; do
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        done
    else
        echo "NO_CANDIDATE_TABLES_FOUND"
    fi
} > "$TMP_DB_RAW"

# ------------------------------------------------------------
# 3. Query API for Quick Links (fallback)
# ------------------------------------------------------------
echo "[export] Querying API for quick links..."
# We try multiple likely endpoints since exact API paths can vary by OpManager build
API_DATA="{}"
for endpoint in \
    "/api/json/admin/getQuickLinks" \
    "/api/json/quicklinks/list" \
    "/api/json/device/getQuickLinks"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | grep -q "{"; then
        API_DATA="$RESP"
        echo "[export] Fetched quick links from API: $endpoint"
        break
    fi
done
echo "$API_DATA" > "$TMP_API_RAW"

# ------------------------------------------------------------
# 4. Assemble Result JSON
# ------------------------------------------------------------
echo "[export] Assembling final result JSON..."

python3 << 'PYEOF'
import json, sys

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

db_raw = load_text("/tmp/_ql_db_raw.txt")
api_raw = load_json("/tmp/_ql_api_raw.json")

result = {
    "db_raw": db_raw,
    "api_raw": api_raw
}

tmp_out = "/tmp/quick_links_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final location securely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/quick_links_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/quick_links_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Clean up temporary files
rm -f "$TMP_DB_RAW" "$TMP_API_RAW" "/tmp/quick_links_result_tmp.json" || true

echo "[export] === Export Complete ==="