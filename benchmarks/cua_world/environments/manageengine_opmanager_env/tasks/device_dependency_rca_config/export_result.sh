#!/bin/bash
# export_result.sh — Device Dependency Map Configuration for Root Cause Analysis
# Collects device list and dependency tables from OpManager database & API,
# then writes /tmp/device_dependency_result.json

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/device_dependency_result.json"
TMP_DEVICES_API="/tmp/_api_devices.json"
TMP_DEVICES_DB="/tmp/_db_devices.txt"
TMP_DEPS_DB="/tmp/_db_deps.txt"

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
echo "[export] Fetching device list via API..."
opmanager_api_get "/api/json/device/listDevices" > "$TMP_DEVICES_API" 2>/dev/null || \
    curl -sf "http://localhost:8060/api/json/device/listDevices?apiKey=${API_KEY}" \
         > "$TMP_DEVICES_API" 2>/dev/null || \
    echo '{}' > "$TMP_DEVICES_API"

# ------------------------------------------------------------
# 2. Query DB for Managed Objects / Devices
# ------------------------------------------------------------
echo "[export] Querying DB for devices..."
DEVICE_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%managedobject%' OR tablename ILIKE '%topo%' OR tablename ILIKE '%device%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DEVICE / MANAGED OBJECT TABLES ==="
    for tbl in $DEVICE_TABLES; do
        if [[ "$tbl" == *"managedobject"* || "$tbl" == *"device"* ]]; then
            echo ""
            echo "--- TABLE: $tbl ---"
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 500;" 2>/dev/null || true
        fi
    done
} > "$TMP_DEVICES_DB" 2>&1

# ------------------------------------------------------------
# 3. Query DB for Dependency / Topology relationships
# ------------------------------------------------------------
echo "[export] Querying DB for dependency relationships..."
DEP_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%depend%' OR tablename ILIKE '%parent%' OR tablename ILIKE '%relation%' OR tablename ILIKE '%hierarch%' OR tablename ILIKE '%topo%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

{
    echo "=== DEPENDENCY / TOPOLOGY TABLES ==="
    for tbl in $DEP_TABLES; do
        echo ""
        echo "--- TABLE: $tbl ---"
        # We fetch up to 1000 rows for mapping tables
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 1000;" 2>/dev/null || true
    done
} > "$TMP_DEPS_DB" 2>&1

# ------------------------------------------------------------
# 4. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

python3 << 'PYEOF'
import json, os

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

api_devices = load_json("/tmp/_api_devices.json")
db_devices = load_text("/tmp/_db_devices.txt")
db_deps = load_text("/tmp/_db_deps.txt")

result = {
    "api_devices": api_devices,
    "db_devices_raw": db_devices,
    "db_dependencies_raw": db_deps,
    "timestamp": os.popen("date -Iseconds").read().strip()
}

tmp_out = "/tmp/device_dependency_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/device_dependency_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/device_dependency_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result successfully written to $RESULT_FILE"

# Clean up temporary files
rm -f "$TMP_DEVICES_API" "$TMP_DEVICES_DB" "$TMP_DEPS_DB" "/tmp/device_dependency_result_tmp.json" 2>/dev/null || true