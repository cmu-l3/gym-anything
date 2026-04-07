#!/bin/bash
# export_result.sh — Mail Server and Proxy Configuration
# Queries OpManager DB and API to dump system settings, writing to JSON.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/mail_proxy_system_config_result.json"
TMP_DB_RAW="/tmp/_sysconfig_db_raw.txt"
TMP_API_MAIL="/tmp/_sysconfig_api_mail.json"
TMP_API_PROXY="/tmp/_sysconfig_api_proxy.json"
TMP_API_GEN="/tmp/_sysconfig_api_gen.json"

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
echo "[export] API key present: $([ -n "$API_KEY" ] && echo yes || echo no)"

# ------------------------------------------------------------
# 2. Query OpManager API for settings
# ------------------------------------------------------------
echo "[export] Fetching settings from API..."

# A. Mail Server
echo '{}' > "$TMP_API_MAIL"
for endpoint in "/api/json/admin/getMailServerSettings" "/api/json/settings/getMailServerSettings" "/api/json/mailserver/getSettings"; do
    RESP=$(curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | grep -qi "mail"; then
        echo "$RESP" > "$TMP_API_MAIL"
        echo "[export] Mail settings fetched from $endpoint"
        break
    fi
done

# B. Proxy Settings
echo '{}' > "$TMP_API_PROXY"
for endpoint in "/api/json/admin/getProxySettings" "/api/json/settings/getProxySettings" "/api/json/proxy/getSettings"; do
    RESP=$(curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | grep -qi "proxy"; then
        echo "$RESP" > "$TMP_API_PROXY"
        echo "[export] Proxy settings fetched from $endpoint"
        break
    fi
done

# C. General/Rebranding Settings
echo '{}' > "$TMP_API_GEN"
for endpoint in "/api/json/admin/getGeneralSettings" "/api/json/settings/getGeneralSettings" "/api/json/admin/getRebrandingSettings"; do
    RESP=$(curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ]; then
        echo "$RESP" > "$TMP_API_GEN"
        echo "[export] General settings fetched from $endpoint"
        break
    fi
done

# ------------------------------------------------------------
# 3. Query PostgreSQL Database
# ------------------------------------------------------------
echo "[export] Querying DB for configuration tables..."

# Find all tables related to configuration, mail, proxy, or rebranding
TARGET_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%mail%' OR tablename ILIKE '%smtp%' OR tablename ILIKE '%proxy%' OR tablename ILIKE '%config%' OR tablename ILIKE '%setting%' OR tablename ILIKE '%rebrand%' OR tablename ILIKE '%company%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

> "$TMP_DB_RAW"

if [ -n "$TARGET_TABLES" ]; then
    echo "[export] Found settings tables: $TARGET_TABLES"
    for tbl in $TARGET_TABLES; do
        echo "=== TABLE: $tbl ===" >> "$TMP_DB_RAW"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 150;" 2>/dev/null >> "$TMP_DB_RAW" || true
        echo "" >> "$TMP_DB_RAW"
    done
else
    echo "[export] WARNING: No configuration tables found in DB." >&2
    echo "NO_CONFIG_TABLES_FOUND" > "$TMP_DB_RAW"
fi

# ------------------------------------------------------------
# 4. Assemble Results into JSON
# ------------------------------------------------------------
echo "[export] Assembling final JSON..."

python3 << 'PYEOF'
import json, sys

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

result = {
    "db_raw": load_text("/tmp/_sysconfig_db_raw.txt"),
    "api_mail": load_json("/tmp/_sysconfig_api_mail.json"),
    "api_proxy": load_json("/tmp/_sysconfig_api_proxy.json"),
    "api_general": load_json("/tmp/_sysconfig_api_gen.json")
}

tmp_out = "/tmp/mail_proxy_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/mail_proxy_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/mail_proxy_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Export complete. Result saved to $RESULT_FILE"

# Clean up
rm -f "$TMP_DB_RAW" "$TMP_API_MAIL" "$TMP_API_PROXY" "$TMP_API_GEN" "/tmp/mail_proxy_result_tmp.json" 2>/dev/null || true