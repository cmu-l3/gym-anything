#!/bin/bash
# export_result.sh — L1 Diagnostic Workflow Automation
# Collects workflow definitions from API and Database, then exports to JSON.

set -euo pipefail

source /workspace/scripts/task_utils.sh

RESULT_FILE="/tmp/workflow_automation_result.json"
TMP_WF_API="/tmp/_wf_api.json"
TMP_WF_DB="/tmp/_wf_db.txt"

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
# 2. Fetch Workflows via API
# ------------------------------------------------------------
echo "[export] Fetching workflows via API..."
WF_FETCHED=0

for endpoint in \
    "/api/json/workflow/listWorkflows" \
    "/api/json/admin/workflows"; do
    RESP=$(opmanager_api_get "$endpoint" 2>/dev/null || \
           curl -sf "http://localhost:8060${endpoint}?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$RESP" ] && echo "$RESP" | python3 -c "import json,sys; d=json.load(sys.stdin); exit(0 if d else 1)" 2>/dev/null; then
        echo "$RESP" > "$TMP_WF_API"
        WF_FETCHED=1
        echo "[export] Workflows fetched from $endpoint"
        break
    fi
done

if [ "$WF_FETCHED" -eq 0 ]; then
    echo '{}' > "$TMP_WF_API"
    echo "[export] WARNING: Could not fetch workflow list from any endpoint." >&2
fi

# ------------------------------------------------------------
# 3. Query DB for Workflow Data
# ------------------------------------------------------------
echo "[export] Querying DB for workflow tables..."

# Find all workflow-related tables
ALL_WF_TABLES=$(opmanager_query "SELECT tablename FROM pg_tables WHERE schemaname='public' AND (tablename ILIKE '%workflow%' OR tablename ILIKE '%wfaction%') ORDER BY tablename;" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)
echo "[export] Discovered workflow tables: $ALL_WF_TABLES"

{
    echo "=== WORKFLOW TABLES DUMP ==="
    for tbl in $ALL_WF_TABLES; do
        if [ -n "$tbl" ]; then
            echo ""
            echo "=== TABLE: $tbl ==="
            opmanager_query_headers "SELECT * FROM \"${tbl}\" LIMIT 200;" 2>/dev/null || true
        fi
    done
} > "$TMP_WF_DB" 2>&1

# ------------------------------------------------------------
# 4. Take final screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/workflow_final_screenshot.png" || true

# ------------------------------------------------------------
# 5. Assemble result JSON
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

wf_api = load_json("/tmp/_wf_api.json")
wf_db = load_text("/tmp/_wf_db.txt")

result = {
    "workflow_api": wf_api,
    "workflow_db_raw": wf_db
}

tmp_out = "/tmp/workflow_automation_result_tmp.json"
with open(tmp_out, "w") as f:
    json.dump(result, f, indent=2)

print(f"[export] Wrote temp result to {tmp_out}")
PYEOF

# Move to final location securely
if declare -f safe_write_json > /dev/null 2>&1; then
    safe_write_json "/tmp/workflow_automation_result_tmp.json" "$RESULT_FILE"
else
    mv "/tmp/workflow_automation_result_tmp.json" "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
fi

echo "[export] Result written to $RESULT_FILE"

# Cleanup
rm -f "$TMP_WF_API" "$TMP_WF_DB" "/tmp/workflow_automation_result_tmp.json" || true