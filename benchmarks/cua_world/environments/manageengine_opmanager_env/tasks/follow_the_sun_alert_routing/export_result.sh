#!/bin/bash
# export_result.sh — Follow-the-Sun Alert Routing
# Queries the OpManager DB and API for notification profiles and time windows,
# then writes /tmp/follow_the_sun_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/follow_the_sun_result.json"
TMP_NOTIF_DB="/tmp/_fts_notif_db.txt"
TMP_NOTIF_API="/tmp/_fts_notif_api.json"

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
export API_KEY="$API_KEY"

# ------------------------------------------------------------
# 1. Query DB for notification and schedule profiles
# ------------------------------------------------------------
echo "[export] Querying DB for notification profiles and schedules..."

# Dump relevant tables to text
{
    # Discover notification/alert tables
    ALL_NOTIF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%alertprofile%' OR tablename ILIKE '%schedule%' OR tablename ILIKE '%timewindow%' OR tablename ILIKE '%email%' OR tablename ILIKE '%action%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

    echo "=== NOTIFICATION AND SCHEDULE TABLES ==="
    echo "Tables: $ALL_NOTIF_TABLES"
    echo ""

    for tbl in $ALL_NOTIF_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        echo ""
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

# Also try to fetch details for each profile if possible
# (If API gives list of profiles with IDs, fetch specific details to get schedule info)
python3 << 'PYEOF'
import json, os, subprocess

api_key = os.environ.get("API_KEY", "")
try:
    with open("/tmp/_fts_notif_api.json") as f:
        data = json.load(f)
        
    profiles = data if isinstance(data, list) else data.get("data", data.get("notificationProfiles", []))
    if isinstance(profiles, list):
        for p in profiles:
            pid = p.get("profileId") or p.get("id")
            if pid:
                url = f"http://localhost:8060/api/json/notification/getNotificationProfile?apiKey={api_key}&profileId={pid}"
                try:
                    out = subprocess.check_output(["curl", "-sf", url])
                    p["_details_"] = json.loads(out)
                except:
                    pass
        
    with open("/tmp/_fts_notif_api.json", "w") as f:
        json.dump(data, f)
except Exception as e:
    pass
PYEOF

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

notif_db  = load_text("/tmp/_fts_notif_db.txt")
notif_api = load_json("/tmp/_fts_notif_api.json")

result = {
    "notification_profiles_db_raw": notif_db,
    "notification_profiles_api": notif_api
}

tmp_out = "/tmp/follow_the_sun_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/follow_the_sun_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/follow_the_sun_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_NOTIF_DB" "$TMP_NOTIF_API" || true