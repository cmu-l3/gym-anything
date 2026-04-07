#!/bin/bash
echo "=== Setting up implement_security_analytics_tracking task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any existing .well-known directory or security.txt to ensure a clean state
sudo rm -rf /opt/socioboard/socioboard-web-php/public/.well-known 2>/dev/null || true

# Wait for Socioboard to be ready
echo "Waiting for Socioboard HTTP service..."
if ! wait_for_http "http://localhost/" 120; then
  echo "WARNING: Socioboard not fully reachable at http://localhost/ yet, but continuing setup."
fi

# Ensure Firefox is running so the agent can browse the app to test its changes
echo "Starting Firefox..."
ensure_firefox_running "http://localhost/"

# Take initial screenshot showing the app is running and Firefox is open
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png ga

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="