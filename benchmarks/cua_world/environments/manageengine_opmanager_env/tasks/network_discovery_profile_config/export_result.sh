#!/bin/bash
# export_result.sh — Automated Network Discovery Profile Configuration
# Collects discovery profile and credential data from API and DB.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/discovery_profile_result.json"

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

echo "[export] Fetching Discovery rules and credentials from API..."
curl -sf "http://localhost:8060/api/json/discovery/listDiscoveryRules?apiKey=${API_KEY}" 2>/dev/null > /tmp/_discovery_api_1.json || echo "{}" > /tmp/_discovery_api_1.json
curl -sf "http://localhost:8060/api/json/discovery/listProfiles?apiKey=${API_KEY}" 2>/dev/null > /tmp/_discovery_api_2.json || echo "{}" > /tmp/_discovery_api_2.json
curl -sf "http://localhost:8060/api/json/admin/listCredentials?apiKey=${API_KEY}" 2>/dev/null > /tmp/_cred_api_1.json || echo "{}" > /tmp/_cred_api_1.json
curl -sf "http://localhost:8060/api/json/snmp/listCredentials?apiKey=${API_KEY}" 2>/dev/null > /tmp/_cred_api_2.json || echo "{}" > /tmp/_cred_api_2.json

# ------------------------------------------------------------
# Query DB for all tables related to discovery and credentials
# ------------------------------------------------------------
echo "[export] Querying DB for discovery and credential tables..."

{
    DISCOV_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%discov%' OR tablename ILIKE '%scan%' OR tablename ILIKE '%network_range%' OR tablename ILIKE '%ip_range%' OR tablename ILIKE '%credential%' OR tablename ILIKE '%snmp%' OR tablename ILIKE '%community%');" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    
    echo "=== DISCOVERY AND CREDENTIAL TABLES ==="
    echo "Tables found: $DISCOV_TABLES"
    echo ""
    
    for tbl in $DISCOV_TABLES; do
        echo "=== TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
    done
} > /tmp/_discov_db.txt 2>&1

# ------------------------------------------------------------
# Assemble final JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json

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

result = {
    "db_raw": load_text("/tmp/_discov_db.txt"),
    "discovery_api_1": load_json("/tmp/_discovery_api_1.json"),
    "discovery_api_2": load_json("/tmp/_discovery_api_2.json"),
    "cred_api_1": load_json("/tmp/_cred_api_1.json"),
    "cred_api_2": load_json("/tmp/_cred_api_2.json")
}

with open("/tmp/discovery_profile_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

take_screenshot /tmp/task_final.png || true
echo "[export] Result written to $RESULT_FILE"
echo "[export] Export complete."