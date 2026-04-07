#!/bin/bash
# Setup for "configure_alert_whitelist" task
# Ensures EventLog Analyzer is running and Firefox is open

echo "=== Setting up Configure Alert Whitelist task ==="

# Source shared utilities
# Do NOT use set -euo pipefail
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Remove any existing verification file
rm -f /home/ga/whitelist_config.txt

# Ensure EventLog Analyzer is running (this waits up to 900s if needed)
wait_for_eventlog_analyzer

# We want the agent to find the settings, so we start at the Dashboard
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Dismiss any "What's New" or onboarding dialogs
if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
    # Click somewhere neutral to ensure focus isn't on a popup
    DISPLAY=:1 xdotool mousemove 10 10 click 1 2>/dev/null || true
fi

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo ""
echo "=== Configure Alert Whitelist Task Ready ==="
echo ""
echo "Goal: Whitelist IP 172.16.0.50 in the Correlation/Alert settings."
echo "1. Find the Whitelist section."
echo "2. Add IP: 172.16.0.50"
echo "3. Description: Authorized_Nessus_Scanner"
echo "4. Create file /home/ga/whitelist_config.txt with these details."
echo ""