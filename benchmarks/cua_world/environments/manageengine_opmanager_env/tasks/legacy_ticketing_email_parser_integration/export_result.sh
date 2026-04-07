#!/bin/bash
# export_result.sh — Legacy Ticketing Email Parser Integration
# Extracts notification profiles from OpManager DB and API for verification.

echo "[export] === Exporting Results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/ticketing_parser_result.json"
TMP_DB="/tmp/_email_notif_db.txt"
TMP_API="/tmp/_email_notif_api.json"

# ------------------------------------------------------------
# 1. Query Database for Notification Profiles
# ------------------------------------------------------------
echo "[export] Querying DB for notification settings..."
{
    echo "=== DB TABLES ==="
    # Query well-known notification tables directly
    for tbl in NotificationProfile EmailAction ActionParam EMailList AlarmEscalationRule EventRule; do
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
    
    # Discover other notification/action tables dynamically
    NOTIF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%notif%' OR tablename ILIKE '%email%' OR tablename ILIKE '%action%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    
    for tbl in $NOTIF_TABLES; do
        # Skip if already queried
        if [[ ! " NotificationProfile EmailAction ActionParam EMailList AlarmEscalationRule EventRule " =~ " ${tbl} " ]]; then
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
        fi
    done
} > "$TMP_DB" 2>&1

# ------------------------------------------------------------
# 2. Query API for Notification Profiles
# ------------------------------------------------------------
echo "[export] Fetching Notification Profiles from API..."
API_KEY=$(cat /tmp/opmanager_api_key 2>/dev/null | tr -d '[:space:]')
if [ -z "$API_KEY" ]; then
    LOGIN_RESP=$(curl -sf -X POST "http://localhost:8060/apiv2/login" -H "Content-Type: application/x-www-form-urlencoded" -d "username=admin&password=Admin%40123" 2>/dev/null || true)
    if [ -n "$LOGIN_RESP" ]; then
        API_KEY=$(python3 -c "import json, sys; d=json.loads(sys.argv[1]); print(d.get('apiKey', d.get('data', {}).get('apiKey', '')))" "$LOGIN_RESP" 2>/dev/null || true)
    fi
fi

opmanager_api_get "/api/json/notification/listNotificationProfiles" > "$TMP_API" 2>/dev/null || \
curl -sf "http://localhost:8060/api/json/notification/listNotificationProfiles?apiKey=${API_KEY}" > "$TMP_API" 2>/dev/null || echo '{}' > "$TMP_API"

# ------------------------------------------------------------
# 3. Assemble JSON Result
# ------------------------------------------------------------
echo "[export] Assembling JSON result..."
python3 << 'PYEOF'
import json

try:
    with open("/tmp/_email_notif_db.txt") as f:
        db_raw = f.read()
except Exception:
    db_raw = ""

try:
    with open("/tmp/_email_notif_api.json") as f:
        api_data = json.load(f)
except Exception:
    api_data = {}

result = {
    "db_raw": db_raw,
    "api_data": api_data,
    "export_timestamp": __import__("time").time()
}

with open("/tmp/ticketing_parser_result_tmp.json", "w") as f:
    json.dump(result, f)
PYEOF

mv "/tmp/ticketing_parser_result_tmp.json" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || true

# ------------------------------------------------------------
# 4. Final Screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/task_final.png" || true
echo "[export] Result saved to $RESULT_FILE"
echo "[export] === Export complete ==="