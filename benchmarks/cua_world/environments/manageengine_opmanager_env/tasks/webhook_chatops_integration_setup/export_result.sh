#!/bin/bash
# export_result.sh — Webhook ChatOps Integration Setup
# Queries the OpManager DB and API for notification profiles and Webhooks,
# then writes the combined data to /tmp/webhook_profiles_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/webhook_profiles_result.json"
TMP_NOTIF_DB="/tmp/_webhook_notif_db.txt"
TMP_NOTIF_API="/tmp/_webhook_notif_api.json"

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
# 1. Query DB for Webhook / notification profiles
# ------------------------------------------------------------
echo "[export] Querying DB for Webhook & Notification tables..."

# Enumerate tables that might hold notification profiles or webhook configurations
ALL_TARGET_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%webhook%' OR tablename ILIKE '%alertprofile%' OR tablename ILIKE '%action%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered relevant tables: $ALL_TARGET_TABLES"

{
    echo "=== NOTIFICATION & WEBHOOK DB DUMP ==="
    echo "Tables scanned: $ALL_TARGET_TABLES"
    echo ""
    
    # Dump up to 10 matching tables to ensure we catch the profiles and URLs
    TABLE_COUNT=0
    for tbl in $ALL_TARGET_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 15 ]; then
            break
        fi
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 300;" 2>/dev/null || true
    done
} > "$TMP_NOTIF_DB" 2>&1

# ------------------------------------------------------------
# 2. Try the OpManager API for notification profiles
# ------------------------------------------------------------
echo "[export] Querying notification profiles via API..."
NOTIF_API_RESP=$(opmanager_api_get "/api/json/notification/listNotificationProfiles" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" \
         2>/dev/null || \
    echo '{}')
echo "$NOTIF_API_RESP" > "$TMP_NOTIF_API"

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

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

notif_db  = load_text("/tmp/_webhook_notif_db.txt")
notif_api = load_json("/tmp/_webhook_notif_api.json")

result = {
    "notification_profiles_db_raw": notif_db,
    "notification_profiles_api": notif_api
}

tmp_out = "/tmp/webhook_profiles_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/webhook_profiles_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/webhook_profiles_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Take a final screenshot
take_screenshot "/tmp/webhook_export_screenshot.png" || true

# Cleanup temp files
rm -f "$TMP_NOTIF_DB" "$TMP_NOTIF_API" || true