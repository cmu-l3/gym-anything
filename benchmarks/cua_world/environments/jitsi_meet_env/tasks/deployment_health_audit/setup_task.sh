#!/bin/bash
set -e
echo "=== Setting up Jitsi Meet Deployment Health Audit ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Jitsi is running (this environment should have it, but verification is good)
if ! docker ps | grep -q "jitsi-web"; then
    echo "Starting Jitsi containers..."
    cd /home/ga/jitsi && docker compose up -d
    wait_for_http "http://localhost:8080" 120
fi

# 3. Clean up any previous report
rm -f /home/ga/jitsi_audit_report.txt

# 4. Open Firefox to the home page
restart_firefox "http://localhost:8080" 10
maximize_firefox
focus_firefox

# 5. Open a terminal for the user (since they need to run docker commands)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    DISPLAY=:1 gnome-terminal --geometry=100x24+200+200 &
    sleep 2
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="