#!/bin/bash
set -e
echo "=== Setting up generate_api_token task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure FreeScout is running and accessible
wait_for_freescout 60 || true

# Clean up any existing token with the target name to prevent ambiguity
# We want to ensure the agent creates a NEW one
echo "Cleaning up old tokens..."
fs_query "DELETE FROM api_tokens WHERE name = 'MetricsDash'" 2>/dev/null || true

# Ensure admin user exists
ADMIN_ID=$(find_user_by_email "admin@helpdesk.local" | cut -f1)
if [ -z "$ADMIN_ID" ]; then
    echo "ERROR: Admin user not found!"
    exit 1
fi
echo "Admin ID: $ADMIN_ID"

# Clean up output file if it exists
rm -f "/home/ga/metrics_token.txt"

# Launch Firefox
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox 'http://localhost:8080' > /tmp/firefox.log 2>&1 &"
    sleep 5
fi

# Wait for window
wait_for_window "firefox|mozilla|freescout" 30
focus_firefox

# Ensure logged in (helper handles login page detection)
ensure_logged_in

# Navigate to dashboard
navigate_to_url "http://localhost:8080/conversations"
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="