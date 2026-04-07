#!/bin/bash
# export_result.sh — NOC Monitoring Gap Remediation
# Collects device groups, URL monitors, and notification profiles,
# then writes /tmp/noc_monitoring_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/noc_monitoring_result.json"
TMP_GROUPS="/tmp/_noc_groups.json"
TMP_MONITORS="/tmp/_noc_monitors.json"
TMP_NOTIF_DB="/tmp/_noc_notif_db.txt"
TMP_NOTIF_API="/tmp/_noc_notif_api.json"

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
# 1. Fetch device groups
# ------------------------------------------------------------
echo "[export] Fetching device groups..."
opmanager_api_get "/api/json/group/listGroups" > "$TMP_GROUPS" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" \
         > "$TMP_GROUPS" 2>/dev/null || \
    echo '{}' > "$TMP_GROUPS"

# ------------------------------------------------------------
# 2. Fetch URL monitors (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching URL monitors..."
URL_MON_FETCHED=0

for endpoint in \
    "/api/json/url/getURLMonitorList" \
    "/api/json/webmon/listWebMonitors" \
    "/api/json/webmonitor/listWebMonitors"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_MONITORS"
        URL_MON_FETCHED=1
        echo "[export] URL monitors fetched from $endpoint"
        break
    fi
done

if [ "$URL_MON_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_MONITORS"
    echo "[export] WARNING: Could not fetch URL monitors from any endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for notification profiles
# ------------------------------------------------------------
echo "[export] Querying DB for notification profiles..."

# Discover the notification-related table name using opmanager_query()
NOTIF_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%alertprofile%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

if [ -z "$NOTIF_TABLE" ]; then
    # Broader fallback search
    NOTIF_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%profile%' OR tablename ILIKE '%email%' OR tablename ILIKE '%notify%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

if [ -n "$NOTIF_TABLE" ]; then
    echo "[export] Found notification table: $NOTIF_TABLE"
    opmanager_query "SELECT * FROM \"${NOTIF_TABLE}\" LIMIT 200;" 2>/dev/null > "$TMP_NOTIF_DB" || echo "QUERY_FAILED" > "$TMP_NOTIF_DB"
else
    echo "[export] WARNING: No notification profile table found in DB." >&2
    echo "NO_NOTIF_TABLE_FOUND" > "$TMP_NOTIF_DB"
fi

# Also try API endpoint for notification profiles
NOTIF_API_RESP=$(opmanager_api_get "/api/json/notification/listNotificationProfiles" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" \
         2>/dev/null || \
    echo '{}')
echo "$NOTIF_API_RESP" > "$TMP_NOTIF_API"

# ------------------------------------------------------------
# 4. Combine into result JSON
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

groups   = load_json("/tmp/_noc_groups.json")
monitors = load_json("/tmp/_noc_monitors.json")
notif_db = load_text("/tmp/_noc_notif_db.txt")
notif_api = load_json("/tmp/_noc_notif_api.json")

result = {
    "groups_api": groups,
    "url_monitors_api": monitors,
    "notification_profiles_db_raw": notif_db,
    "notification_profiles_api": notif_api
}

tmp_out = "/tmp/noc_monitoring_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/noc_monitoring_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/noc_monitoring_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_GROUPS" "$TMP_MONITORS" "$TMP_NOTIF_DB" "$TMP_NOTIF_API" || true
