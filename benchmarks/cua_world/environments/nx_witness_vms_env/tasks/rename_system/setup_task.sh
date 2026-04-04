#!/bin/bash
echo "=== Setting up rename_system task ==="

source /workspace/scripts/task_utils.sh

# Refresh auth token
refresh_nx_token > /dev/null 2>&1 || true

# Reset system name to 'GymAnythingVMS' (idempotent — ensures agent has something to do)
echo "Resetting system name to 'GymAnythingVMS'..."
TOKEN=$(cat "${NX_TOKEN_FILE}" 2>/dev/null || refresh_nx_token)
curl -sk -X PATCH "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{"systemName": "GymAnythingVMS"}' \
    --max-time 15 > /dev/null 2>&1 || true
echo "System name reset to GymAnythingVMS"

# Verify current system name
CURRENT_NAME=$(curl -sk "${NX_BASE}/rest/v1/system/settings" \
    -H "Authorization: Bearer ${TOKEN}" --max-time 10 | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('systemName','?'))" 2>/dev/null || echo "?")
echo "Current system name: $CURRENT_NAME"

# Ensure Firefox is running and on the Nx Witness Web Admin Settings page
ensure_firefox_running "https://localhost:7001/static/index.html#/settings"
sleep 4
maximize_firefox

# Take initial screenshot for evidence
take_screenshot /tmp/nx_export_video_start.png

echo "=== rename_system task setup complete ==="
echo "Task: Change system name from 'GymAnythingVMS' to 'SecurityCentralVMS'"
echo "Navigate to: Settings → System Administration → General"
echo "Current name: $CURRENT_NAME"
echo "Target name: SecurityCentralVMS"
echo "Web Admin: https://localhost:7001/static/index.html#/settings"
echo "Credentials: admin / Admin1234!"
