#!/bin/bash
# export_result.sh — SNMP Credential Security Audit
# Collects device list and SNMP credential data from the API and DB,
# then writes /tmp/snmp_security_result.json.

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/snmp_security_result.json"
TMP_DEVICES="/tmp/_snmp_devices.json"
TMP_CRED_DB="/tmp/_snmp_cred_db.txt"

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
# 1. Fetch device list from API
# ------------------------------------------------------------
echo "[export] Fetching device list..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES"

# ------------------------------------------------------------
# 2. Query DB for SNMP credential profiles
# ------------------------------------------------------------
echo "[export] Querying DB for SNMP credential tables..."

# Discover SNMP credential-related tables using opmanager_query()
SNMP_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%snmp%' OR tablename ILIKE '%credential%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)

if [ -z "$SNMP_TABLE" ]; then
    SNMP_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename ILIKE '%community%' ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

if [ -z "$SNMP_TABLE" ]; then
    SNMP_TABLE=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%discov%' OR tablename ILIKE '%profile%') ORDER BY tablename LIMIT 1;" 2>/dev/null | head -1 | tr -d ' \t' || true)
fi

# Enumerate all SNMP/credential/community tables
ALL_SNMP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%snmp%' OR tablename ILIKE '%credential%' OR tablename ILIKE '%community%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] All SNMP/credential/community tables: $ALL_SNMP_TABLES"

{
    echo "=== SNMP CREDENTIAL TABLE SEARCH RESULTS ==="
    echo "All candidate tables: $ALL_SNMP_TABLES"
    echo ""

    if [ -n "$SNMP_TABLE" ]; then
        echo "=== PRIMARY TABLE: $SNMP_TABLE ==="
        opmanager_query_headers "SELECT * FROM \"${SNMP_TABLE}\" LIMIT 500;" 2>/dev/null || true
    fi

    # Also dump each additional discovered table
    TABLE_COUNT=0
    for tbl in $ALL_SNMP_TABLES; do
        if [ "$tbl" = "$SNMP_TABLE" ]; then
            continue
        fi
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 4 ]; then
            break
        fi
        echo ""
        echo "=== ADDITIONAL TABLE: $tbl ==="
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 300;" 2>/dev/null || true
    done

    # Dump any additional community/write_community columns from known SNMP tables
    echo ""
    echo "=== COMMUNITY STRING COLUMNS IN SNMP TABLES ==="
    COMM_TABLES=$(opmanager_query "SELECT DISTINCT t.table_name FROM information_schema.tables t JOIN information_schema.columns c ON t.table_name = c.table_name WHERE t.table_schema='public' AND t.table_type='BASE TABLE' AND (c.column_name ILIKE '%community%') ORDER BY t.table_name;" 2>/dev/null | tr -d ' ' | head -10 || true)
    for stbl in $COMM_TABLES; do
        opmanager_query_headers "SELECT * FROM \"${stbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_CRED_DB" 2>&1

# ------------------------------------------------------------
# 3. Combine into result JSON
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

devices_api = load_json("/tmp/_snmp_devices.json")
cred_db_raw = load_text("/tmp/_snmp_cred_db.txt")

result = {
    "devices_api": devices_api,
    "snmp_credentials_db_raw": cred_db_raw,
}

tmp_out = "/tmp/snmp_security_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Use safe_write_json if available, otherwise direct move
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/snmp_security_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/snmp_security_result_tmp.json" "$RESULT_FILE"
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_DEVICES" "$TMP_CRED_DB" || true
