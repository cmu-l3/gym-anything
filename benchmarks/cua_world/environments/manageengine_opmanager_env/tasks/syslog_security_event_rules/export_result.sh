#!/bin/bash
# export_result.sh — Syslog Security Event Processing Rules
# Collects syslog rule data via API, DB, and Configuration files, then writes /tmp/syslog_rules_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/syslog_rules_result.json"
TMP_SYSLOG_API="/tmp/_syslog_api.json"
TMP_SYSLOG_DB="/tmp/_syslog_db.txt"
TMP_SYSLOG_CONF="/tmp/_syslog_conf.txt"

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
# 2. Fetch syslog rules via API (try multiple endpoints)
# ------------------------------------------------------------
echo "[export] Fetching syslog rules via API..."
SYSLOG_FETCHED=0

for endpoint in \
    "/api/json/syslog/listRules" \
    "/api/json/syslog/getRules" \
    "/api/json/monitoring/syslog/rules" \
    "/api/json/admin/syslog/listSyslogRules" \
    "/api/json/syslogRule/list"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_SYSLOG_API"
        SYSLOG_FETCHED=1
        echo "[export] Syslog rules fetched from $endpoint"
        break
    fi
done

if [ "$SYSLOG_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_SYSLOG_API"
    echo "[export] WARNING: Could not fetch syslog rules from any list endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for syslog rule tables
# ------------------------------------------------------------
echo "[export] Querying DB for syslog-related tables..."

# Find all syslog/rule/parser related tables
SYSLOG_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%syslog%' OR tablename ILIKE '%rule%' OR tablename ILIKE '%parser%' OR tablename ILIKE '%filter%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== SYSLOG/RULE TABLES ==="
    if [ -n "$SYSLOG_TABLES" ]; then
        for tbl in $SYSLOG_TABLES; do
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 150;" 2>/dev/null || true
        done
    else
        echo "NO_TABLES_FOUND"
    fi
} > "$TMP_SYSLOG_DB" 2>&1

# ------------------------------------------------------------
# 4. Search Configuration XML files (some rules persist here)
# ------------------------------------------------------------
echo "[export] Searching configuration files for rules..."
OPMANAGER_CONF_DIR=$(cat /tmp/opmanager_install_dir 2>/dev/null || echo "/opt/ManageEngine/OpManager")/conf
if [ -d "$OPMANAGER_CONF_DIR" ]; then
    find "$OPMANAGER_CONF_DIR" -name "*.xml" -exec grep -iH -C 2 "SEC-" {} \; > "$TMP_SYSLOG_CONF" 2>/dev/null || echo "NO_MATCHES" > "$TMP_SYSLOG_CONF"
else
    echo "CONF_DIR_NOT_FOUND" > "$TMP_SYSLOG_CONF"
fi

# ------------------------------------------------------------
# 5. Assemble Result JSON
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

syslog_api = load_json("/tmp/_syslog_api.json")
syslog_db  = load_text("/tmp/_syslog_db.txt")
syslog_conf = load_text("/tmp/_syslog_conf.txt")

result = {
    "syslog_rules_api": syslog_api,
    "syslog_rules_db_raw": syslog_db,
    "syslog_rules_conf_raw": syslog_conf
}

tmp_out = "/tmp/syslog_rules_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final result destination safely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/syslog_rules_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/syslog_rules_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_SYSLOG_API" "$TMP_SYSLOG_DB" "$TMP_SYSLOG_CONF" || true