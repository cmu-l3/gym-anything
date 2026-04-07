#!/bin/bash
set -e
echo "=== Exporting service monitor results ==="

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/service_monitor_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final_state.png || true

# Initialize JSON output map
API_RAW=""
DB_RAW=""

# ============================================================
# 1. API-based monitor discovery
# ============================================================
echo "Querying OpManager API for monitors..."

API_KEY=$(cat /tmp/opmanager_api_key 2>/dev/null || echo "")

API_ENDPOINTS=(
    "/api/json/monitor/listMonitors"
    "/api/json/servicemonitor/listServiceMonitors"
    "/api/json/service/listServices"
    "/api/json/device/listDevices"
)

for endpoint in "${API_ENDPOINTS[@]}"; do
    if [ -n "$API_KEY" ]; then
        RESP=$(curl -s --max-time 15 "${OPMANAGER_URL}${endpoint}?apiKey=${API_KEY}" 2>/dev/null || echo "")
    else
        opmanager_login
        RESP=$(curl -s --max-time 15 -b /tmp/opmanager_task_cookies.txt "${OPMANAGER_URL}${endpoint}" 2>/dev/null || echo "")
    fi

    if [ -n "$RESP" ] && [ "$RESP" != "null" ]; then
        API_RAW="${API_RAW}\n--- ${endpoint} ---\n${RESP}\n"
    fi
done

echo "API queries complete."

# ============================================================
# 2. Database-based monitor discovery (broad scan)
# ============================================================
echo "Scanning OpManager database for service monitors..."

PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")

if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
    cd /tmp

    MONITOR_TABLES=$(sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -t -A -c "
        SELECT tablename FROM pg_tables
        WHERE schemaname = 'public'
        AND (
            tablename ILIKE '%monitor%'
            OR tablename ILIKE '%service%'
            OR tablename ILIKE '%probe%'
            OR tablename ILIKE '%port%'
        )
        ORDER BY tablename;" 2>/dev/null || echo "")

    for table in $MONITOR_TABLES; do
        if [ -n "$table" ]; then
            TABLE_DATA=$(sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "
                SELECT * FROM \"$table\" LIMIT 500;" 2>/dev/null || echo "")
            if [ -n "$TABLE_DATA" ]; then
                DB_RAW="${DB_RAW}\n=== TABLE: ${table} ===\n${TABLE_DATA}\n"
            fi
        fi
    done
fi

echo "Database scan complete."

# ============================================================
# 3. Build Result JSON
# ============================================================
echo "Building result JSON..."

# Write raw content to temp files safely to process via Python
cat > /tmp/api_raw.txt <<< "$API_RAW"
cat > /tmp/db_raw.txt <<< "$DB_RAW"

python3 << 'PYEOF'
import json

try:
    with open('/tmp/api_raw.txt', 'r') as f:
        api_data = f.read()
except:
    api_data = ""

try:
    with open('/tmp/db_raw.txt', 'r') as f:
        db_data = f.read()
except:
    db_data = ""

result = {
    "api_raw": api_data,
    "db_raw": db_data
}

with open('/tmp/service_monitor_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/service_monitor_result.json 2>/dev/null || sudo chmod 666 /tmp/service_monitor_result.json 2>/dev/null || true

echo "=== Export complete ==="