#!/bin/bash
# setup_task.sh — MSP Tenant Scope Segregation
# Prepares the environment, records the start time, and opens the UI.

source /workspace/scripts/task_utils.sh

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
# Remove any pre-existing Globex configurations to ensure clean state
# ------------------------------------------------------------
API_KEY=""
if [ -f /tmp/opmanager_api_key ]; then
    API_KEY="$(cat /tmp/opmanager_api_key | tr -d '[:space:]')"
fi

if [ -n "$API_KEY" ]; then
    # Try to delete 'globex_noc' user if it exists
    curl -sf -X POST "http://localhost:8060/api/json/admin/deleteUser?apiKey=${API_KEY}&userName=globex_noc" -o /dev/null 2>/dev/null || true
    
    # Get and delete 'Globex-Infrastructure' Business View if it exists
    BV_JSON=$(curl -sf "http://localhost:8060/api/json/businessview/listBusinessViews?apiKey=${API_KEY}" 2>/dev/null || true)
    if [ -n "$BV_JSON" ]; then
        BV_ID=$(python3 -c "
import json, sys
try:
    data = json.loads(sys.argv[1])
    bvs = data if isinstance(data, list) else data.get('data', data.get('businessViews', []))
    for bv in bvs:
        if isinstance(bv, dict) and bv.get('name','') == 'Globex-Infrastructure':
            print(bv.get('name', ''))
            break
except Exception:
    pass
" "$BV_JSON" 2>/dev/null || true)
        if [ -n "$BV_ID" ]; then
            curl -sf -X POST "http://localhost:8060/api/json/businessview/deleteBusinessView?apiKey=${API_KEY}&name=Globex-Infrastructure" -o /dev/null 2>/dev/null || true
        fi
    fi
fi

# ------------------------------------------------------------
# Record task start timestamp
# ------------------------------------------------------------
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/msp_tenant_task_start.txt
echo "[setup] Task start time recorded."

# ------------------------------------------------------------
# Ensure Firefox is open on OpManager dashboard
# ------------------------------------------------------------
echo "[setup] Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3 || true

# ------------------------------------------------------------
# Take initial screenshot
# ------------------------------------------------------------
take_screenshot "/tmp/msp_tenant_setup_screenshot.png" || true

echo "[setup] === MSP Tenant Scope Segregation Task Setup Complete ==="
echo ""
echo "Task: Multi-Tenant Data Segregation"
echo ""
echo "  1. Create Business View:"
echo "     Name: Globex-Infrastructure"
echo "     Add Device: 127.0.0.1"
echo ""
echo "  2. Create User Account:"
echo "     Username: globex_noc"
echo "     Password: Globex@Secure123"
echo "     Role: Operator (or Read Only)"
echo "     Scope: Restrict access exclusively to the 'Globex-Infrastructure' Business View"
echo ""