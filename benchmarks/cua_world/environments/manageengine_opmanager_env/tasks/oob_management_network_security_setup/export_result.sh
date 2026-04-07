#!/bin/bash
# export_result.sh — OOB Management Network Security Setup
# Exports configuration data from the DB to verify Proxy and RADIUS settings.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/oob_security_result.json"
TMP_PROXY_DB="/tmp/_proxy_db.txt"
TMP_RADIUS_DB="/tmp/_radius_db.txt"

# ------------------------------------------------------------
# 1. Query DB for Proxy Settings
# ------------------------------------------------------------
echo "[export] Querying DB for proxy settings..."

PROXY_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%proxy%' OR tablename ILIKE '%globalsetting%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] Proxy candidate tables: $PROXY_TABLES"

{
    echo "=== PROXY TABLES ==="
    for tbl in $PROXY_TABLES; do
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 100;" 2>/dev/null || true
    done
} > "$TMP_PROXY_DB" 2>&1

# ------------------------------------------------------------
# 2. Query DB for RADIUS Settings
# ------------------------------------------------------------
echo "[export] Querying DB for RADIUS authentication settings..."

RADIUS_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%radius%' OR tablename ILIKE '%auth%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)

echo "[export] RADIUS candidate tables: $RADIUS_TABLES"

{
    echo "=== RADIUS & AUTH TABLES ==="
    for tbl in $RADIUS_TABLES; do
        echo "--- TABLE: $tbl ---"
        opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
    done
} > "$TMP_RADIUS_DB" 2>&1

# ------------------------------------------------------------
# 3. Assemble result JSON
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

proxy_db = load_text("/tmp/_proxy_db.txt")
radius_db = load_text("/tmp/_radius_db.txt")

result = {
    "proxy_db_raw": proxy_db,
    "radius_db_raw": radius_db
}

tmp_out = "/tmp/oob_security_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final location securely
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "/tmp/oob_security_result_tmp.json" "$RESULT_FILE" 2>/dev/null || sudo cp "/tmp/oob_security_result_tmp.json" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true

# Cleanup temp files
rm -f "$TMP_PROXY_DB" "$TMP_RADIUS_DB" "/tmp/oob_security_result_tmp.json" || true

echo "[export] Result written to $RESULT_FILE"