#!/bin/bash
# Setup for "create_alert_rule" task
# Opens Firefox to the EventLog Analyzer Alerts page

echo "=== Setting up Create Alert Rule task ==="

# Do NOT use set -euo pipefail (cross-cutting pattern #25)
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Navigate Firefox to EventLog Analyzer Alerts section
ensure_firefox_on_ela "/event/AppsHome.do#/alerts/alert"
sleep 3

# Take initial screenshot
take_screenshot /tmp/create_alert_rule_start.png

echo ""
echo "=== Create Alert Rule Task Ready ==="
echo ""
echo "Instructions:"
echo "  EventLog Analyzer Alerts page is open in Firefox."
echo "  You are logged in as admin."
echo "  Click 'Add Alert Profile' button."
echo "  Create a new alert profile with:"
echo "    - Name: SSH Brute Force Detection"
echo "    - Severity: Critical"
echo "    - Alert Type: Threshold based"
echo ""
