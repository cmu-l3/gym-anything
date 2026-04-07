#!/bin/bash
# export_result.sh — Discovery Rule Engine Automation
# Collects rule and group data via API and DB, then writes /tmp/discovery_rule_result.json

set -euo pipefail
source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/discovery_rule_result.json"
TMP_DB_RAW="/tmp/_discovery_db_raw.txt"
TMP_API_RULES="/tmp/_discovery_api_rules.json"
TMP_API_GROUPS="/tmp/_discovery_api_groups.json"

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
# 2. Fetch Rules and Groups via API
# ------------------------------------------------------------
echo "[export] Fetching Rules via API..."
opmanager_api_get "/api/json/ruleengine/listRules" > "$TMP_API_RULES" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/ruleengine/listRules?apiKey=${API_KEY}" > "$TMP_API_RULES" 2>/dev/null || \
    echo '{}' > "$TMP_API_RULES"

echo "[export] Fetching Groups via API..."
# Try multiple endpoints for groups
curl -sf "http://localhost:8060/api/json/group/listGroups?apiKey=${API_KEY}" > "$TMP_API_GROUPS" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/admin/getCustomGroups?apiKey=${API_KEY}" > "$TMP_API_GROUPS" 2>/dev/null || \
    echo '{}' > "$TMP_API_GROUPS"

# ------------------------------------------------------------
# 3. Query PostgreSQL DB for Group and Rule Tables
# ------------------------------------------------------------
echo "[export] Querying DB for relevant tables..."

GROUP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%group%' OR tablename ILIKE '%customview%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
RULE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%rule%' OR tablename ILIKE '%criteria%' OR tablename ILIKE '%action%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== GROUP TABLES ==="
    for tbl in $GROUP_TABLES; do
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 300;" 2>/dev/null || true
    done
    
    echo "=== RULE TABLES ==="
    for tbl in $RULE_TABLES; do
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 300;" 2>/dev/null || true
    done
} > "$TMP_DB_RAW" 2>&1

# ------------------------------------------------------------
# 4. Assemble Result JSON
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

api_rules = load_json("/tmp/_discovery_api_rules.json")
api_groups = load_json("/tmp/_discovery_api_groups.json")
db_raw = load_text("/tmp/_discovery_db_raw.txt")

result = {
    "api_rules": api_rules,
    "api_groups": api_groups,
    "db_raw": db_raw
}

tmp_out = "/tmp/discovery_rule_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move payload to final destination, handling possible permissions
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/discovery_rule_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/discovery_rule_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo mv "/tmp/discovery_rule_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

# Clean up
rm -f "$TMP_DB_RAW" "$TMP_API_RULES" "$TMP_API_GROUPS" || true
take_screenshot "/tmp/discovery_final_screenshot.png" || true

echo "[export] Result written to $RESULT_FILE"