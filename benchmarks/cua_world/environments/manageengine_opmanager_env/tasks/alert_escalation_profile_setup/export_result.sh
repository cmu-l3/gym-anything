#!/bin/bash
# export_result.sh — Alert Escalation Profile Setup
# Queries the OpManager DB and API for notification profiles,
# then writes /tmp/alert_escalation_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/alert_escalation_result.json"
TMP_NOTIF_DB="/tmp/_alert_notif_db.txt"
TMP_NOTIF_API="/tmp/_alert_notif_api.json"

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
# 1. Query DB for notification profiles (dynamic table discovery)
# ------------------------------------------------------------
echo "[export] Querying DB for notification profiles..."

# Primary discovery using opmanager_query()
NOTIF_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%alertprofile%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

# Secondary discovery: broader terms
if [ -z "$NOTIF_TABLE" ]; then
    NOTIF_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%profile%' OR tablename ILIKE '%email%' OR tablename ILIKE '%notify%' OR tablename ILIKE '%alert%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

if [ -n "$NOTIF_TABLE" ]; then
    echo "[export] Found notification table: $NOTIF_TABLE"
    opmanager_query "SELECT * FROM \"${NOTIF_TABLE}\" LIMIT 200;" 2>/dev/null > "$TMP_NOTIF_DB" || echo "QUERY_FAILED" > "$TMP_NOTIF_DB"
else
    echo "[export] WARNING: No notification profile table found in DB." >&2
    echo "NO_NOTIF_TABLE_FOUND" > "$TMP_NOTIF_DB"
fi

# ------------------------------------------------------------
# 2. Also try the OpManager API for notification profiles
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

notif_db  = load_text("/tmp/_alert_notif_db.txt")
notif_api = load_json("/tmp/_alert_notif_api.json")

result = {
    "notification_profiles_db_raw": notif_db,
    "notification_profiles_api": notif_api
}

tmp_out = "/tmp/alert_escalation_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/alert_escalation_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/alert_escalation_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_NOTIF_DB" "$TMP_NOTIF_API" || true
