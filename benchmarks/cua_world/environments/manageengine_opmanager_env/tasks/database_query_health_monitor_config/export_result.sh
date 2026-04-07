#!/bin/bash
# export_result.sh — Database Query Health Monitor Configuration
# Collects custom monitor and query data from the OpManager API and DB,
# then writes /tmp/db_query_monitor_result.json.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/db_query_monitor_result.json"
TMP_API="/tmp/_db_query_api.json"
TMP_DB_RAW="/tmp/_db_query_raw.txt"

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
# 1. Fetch DB Query Monitors via API (Best Effort)
# ------------------------------------------------------------
echo "[export] Fetching DB Query Monitors from API..."
API_FETCHED=0

for endpoint in \
    "/api/json/admin/getDBQueryMonitors" \
    "/api/json/dbmonitor/list" \
    "/api/json/admin/getCustomMonitors" \
    "/api/json/admin/listDBMonitors"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_API"
        API_FETCHED=1
        echo "[export] Monitors fetched from $endpoint"
        break
    fi
done

if [ "$API_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_API"
    echo "[export] WARNING: Could not fetch DB monitors from known API endpoints." >&2
fi

# ------------------------------------------------------------
# 2. Query PostgreSQL Database (Comprehensive Search)
# ------------------------------------------------------------
echo "[export] Querying DB for monitor configurations..."

> "$TMP_DB_RAW"

PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null || echo "")
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")

if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
    # Strategy A: Dump matching tables (query, sql, dbmonitor, template)
    ALL_MONITOR_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%query%' OR tablename ILIKE '%sql%' OR tablename ILIKE '%monitor%' OR tablename ILIKE '%template%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
    
    echo "=== CANDIDATE TABLES ===" >> "$TMP_DB_RAW"
    echo "$ALL_MONITOR_TABLES" >> "$TMP_DB_RAW"
    echo "" >> "$TMP_DB_RAW"

    TABLE_COUNT=0
    for tbl in $ALL_MONITOR_TABLES; do
        TABLE_COUNT=$((TABLE_COUNT + 1))
        if [ "$TABLE_COUNT" -gt 15 ]; then
            break # Avoid dumping too much if schema has tons of 'monitor' tables
        fi
        echo "=== TABLE: $tbl ===" >> "$TMP_DB_RAW"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null >> "$TMP_DB_RAW" || true
        echo "" >> "$TMP_DB_RAW"
    done

    # Strategy B: Hard grep across the entire database dump to guarantee we find the SQL strings if they exist
    echo "=== FULL DB TEXT SEARCH ===" >> "$TMP_DB_RAW"
    sudo -u postgres "$PG_BIN" -p "$PG_PORT" pg_dump -U postgres OpManagerDB -a --inserts 2>/dev/null | grep -iE 'pg_stat_activity|innodb_trx|PostgreSQL-Connection-Count|MySQL-Transaction-Queue' >> "$TMP_DB_RAW" || true
else
    echo "NO_DATABASE_BINARY_FOUND" >> "$TMP_DB_RAW"
fi

# ------------------------------------------------------------
# 3. Assemble result JSON
# ------------------------------------------------------------
echo "[export] Assembling result JSON..."

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

api_data = load_json("/tmp/_db_query_api.json")
db_raw   = load_text("/tmp/_db_query_raw.txt")

result = {
    "monitors_api": api_data,
    "db_raw": db_raw
}

tmp_out = "/tmp/db_query_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)
PYEOF

if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/db_query_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/db_query_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup temp files
rm -f "$TMP_API" "$TMP_DB_RAW" "/tmp/db_query_result_tmp.json" || true