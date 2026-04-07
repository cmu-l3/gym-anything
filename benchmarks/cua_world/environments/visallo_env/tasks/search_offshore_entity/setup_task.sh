#!/bin/bash
echo "=== Setting up search_offshore_entity task ==="

source /workspace/scripts/task_utils.sh

# Ensure Visallo is ready
if ! ensure_visallo_ready 30; then
    echo "CRITICAL ERROR: Visallo is not accessible."
    exit 1
fi

date +%s > /tmp/task_start_time

# Restart Firefox, login, and navigate to dashboard
restart_firefox "$VISALLO_URL/"
sleep 2
visallo_login "analyst"

take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Agent should see the Visallo dashboard with search bar at top"
