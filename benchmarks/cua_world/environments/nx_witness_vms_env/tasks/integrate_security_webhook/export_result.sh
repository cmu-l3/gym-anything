#!/bin/bash
set -e
echo "=== Exporting integrate_security_webhook results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ============================================================
# 1. Capture API State (Ground Truth)
# ============================================================
echo "Exporting Event Rules configuration..."
refresh_nx_token > /dev/null 2>&1 || true

# Dump all event rules to JSON
nx_api_get "/rest/v1/eventRules" > /tmp/event_rules_dump.json

# Dump server info (to verify system is running)
nx_api_get "/rest/v1/servers" > /tmp/servers_dump.json

# ============================================================
# 2. Capture Visual Evidence
# ============================================================
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if Desktop Client is running
CLIENT_RUNNING="false"
if pgrep -f "nxwitness" > /dev/null || pgrep -f "applauncher" > /dev/null; then
    CLIENT_RUNNING="true"
fi

# ============================================================
# 3. Create Result JSON
# ============================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "client_running": $CLIENT_RUNNING,
    "event_rules_path": "/tmp/event_rules_dump.json",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

# Move the data dump for the verifier to access via copy_from_env
chmod 666 /tmp/event_rules_dump.json

echo "=== Export complete ==="