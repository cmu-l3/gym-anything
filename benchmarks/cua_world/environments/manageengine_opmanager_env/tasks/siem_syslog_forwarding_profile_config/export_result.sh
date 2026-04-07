#!/bin/bash
# export_result.sh — SIEM Syslog Forwarding Profile Configuration
# Queries the OpManager DB and API for notification and syslog profiles,
# then writes /tmp/siem_syslog_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/siem_syslog_result.json"
TMP_NOTIF_DB="/tmp/_siem_notif_db.txt"
TMP_NOTIF_API="/tmp/_siem_notif_api.json"

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
# 1. Query DB for notification and syslog profiles
# ------------------------------------------------------------
echo "[export] Querying DB for syslog and notification profiles..."

# Discover related tables using opmanager_query()
ALL_NOTIF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%syslog%' OR tablename ILIKE '%alert%' OR tablename ILIKE '%profile%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Discovered candidate tables: $ALL_NOTIF_TABLES"

{
    echo "=== NOTIFICATION & SYSLOG TABLE DUMP ==="
    TABLE_COUNT=0
    for tbl in $ALL_NOTIF_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 15 ]; then
            break # Limit to avoid massive dumps
        fi
        echo ""
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_NOTIF_DB" 2>&1

# ------------------------------------------------------------
# 2. Query notification profiles via API
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

notif_db  = load_text("/tmp/_siem_notif_db.txt")
notif_api = load_json("/tmp/_siem_notif_api.json")

result = {
    "syslog_profiles_db_raw": notif_db,
    "notification_profiles_api": notif_api
}

tmp_out = "/tmp/siem_syslog_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/siem_syslog_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/siem_syslog_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_NOTIF_DB" "$TMP_NOTIF_API" || true