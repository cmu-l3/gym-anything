#!/bin/bash
# setup_task.sh — L1 Diagnostic Workflow Automation
# Waits for OpManager to be ready, cleans up any existing workflows, records start time, and opens the dashboard.

source /workspace/scripts/task_utils.sh

echo "[setup] === Setting up IT Diagnostic Workflow Automation Task ==="

# ------------------------------------------------------------
# 1. Wait for OpManager to be ready
# ------------------------------------------------------------
echo "[setup] Waiting for OpManager to be ready..."
WAIT_TIMEOUT=180
ELAPSED=0
until curl -sf -o /dev/null "http://localhost:8060/"; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    if [ "$ELAPSED" -ge "$WAIT_TIMEOUT" ]; then
        echo "[setup] WARNING: OpManager not ready after ${WAIT_TIMEOUT}s, continuing anyway." >&2
        break
    fi
done
echo "[setup] OpManager is ready."

# ------------------------------------------------------------
# 2. Cleanup: Remove any existing workflow with the target name (Anti-gaming)
# ------------------------------------------------------------
echo "[setup] Removing any pre-existing workflows named 'L1-Automated-Triage'..."

API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

if [ -n "$API_KEY" ]; then
    WORKFLOW_JSON=$(curl -sf "http://localhost:8060/api/json/workflow/listWorkflows?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$WORKFLOW_JSON" ]; then
        WF_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    wfs = data if isinstance(data, list) else data.get('data', data.get('workflows', []))
    for w in wfs:
        if isinstance(w, dict) and w.get('name', w.get('workflowName', '')) == 'L1-Automated-Triage':
            print(w.get('id', w.get('workflowId', '')))
            break
except Exception:
    pass
" "$WORKFLOW_JSON" 2>/dev/null || true)
        if [ -n "$WF_ID" ]; then
            curl -sf -X POST "http://localhost:8060/api/json/workflow/deleteWorkflow?apiKey=${API_KEY}&workflowId=${WF_ID}" -o /dev/null 2>/dev/null || true
            echo "[setup] Deleted existing workflow 'L1-Automated-Triage' (id=${WF_ID})."
        fi
    fi
fi

# Also attempt a direct DB deletion just in case
PG_BIN=$(cat /tmp/opmanager_pg_bin 2>/dev/null)
PG_PORT=$(cat /tmp/opmanager_pg_port 2>/dev/null || echo "13306")
if [ -n "$PG_BIN" ] && [ -f "$PG_BIN" ]; then
    sudo -u postgres "$PG_BIN" -p "$PG_PORT" -U postgres OpManagerDB -c "DELETE FROM Workflow WHERE WORKFLOWNAME = 'L1-Automated-Triage';" 2>/dev/null || true
fi

# ------------------------------------------------------------
# 3. Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/workflow_task_start.txt
date +%s > /tmp/task_start_timestamp
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# 4. Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# Take an initial screenshot
take_screenshot "/tmp/workflow_setup_screenshot.png" || true

echo "[setup] === Task Setup Complete ==="
echo ""
echo "Task: Create 'L1-Automated-Triage' workflow"
echo "Required Actions: Ping, Trace Route"
echo "OpManager Login: admin / Admin@123"