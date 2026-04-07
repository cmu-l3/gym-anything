#!/bin/bash
# Setup for "configure_proxy_server_settings" task

echo "=== Setting up Configure Proxy Server Settings task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Record initial DB state (to prove it wasn't set before)
echo "Recording initial proxy config state..."
ela_db_query "SELECT * FROM SystemConfig WHERE param_name LIKE '%PROXY%'" > /tmp/initial_proxy_state.txt 2>/dev/null || true

# Navigate Firefox to EventLog Analyzer Settings
# We use the main dashboard URL; specific deep links to settings often require authentication redirection
ensure_firefox_on_ela "/event/index.do"
sleep 5

# Attempt to navigate to Settings tab if possible (coordinates based on standard 1920x1080 layout)
# Settings tab is typically top right or a gear icon
# For now, just ensuring the app is open and focused is sufficient as per "Principle 2: Agent Should Know Features"
# But we'll try to focus the window
ensure_firefox_on_ela

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="