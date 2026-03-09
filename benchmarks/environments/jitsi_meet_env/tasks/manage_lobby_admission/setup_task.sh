#!/bin/bash
set -e

echo "=== Setting up manage_lobby_admission task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jitsi is reachable
if ! wait_for_http "${JITSI_BASE_URL:-http://localhost:8080}" 120; then
    echo "ERROR: Jitsi Meet is not reachable"
    exit 1
fi

# 3. Clean up any existing browsers
pkill -f firefox 2>/dev/null || true
pkill -f epiphany 2>/dev/null || true
pkill -f "Web Content" 2>/dev/null || true # Epiphany helper
sleep 2

# 4. Start Firefox (Host) at the home page
# We don't join the room yet; agent must do it to follow instructions
restart_firefox "http://localhost:8080" 8
maximize_firefox
focus_firefox

# 5. Ensure Epiphany is available (check silently)
if ! command -v epiphany-browser >/dev/null 2>&1; then
    echo "WARNING: epiphany-browser not found in path"
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Task ready. Firefox is open."