#!/bin/bash
# Setup for "configure_incident_assignment" task

echo "=== Setting up Configure Incident Assignment task ==="

# Source shared utilities
# Do NOT use set -euo pipefail
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task start time
date +%s > /tmp/task_start_time.txt

# Clean up any previous evidence files
rm -f /home/ga/audit_evidence.csv
rm -f /tmp/rule_configured.png

# Ensure EventLog Analyzer is running
wait_for_eventlog_analyzer

# Navigate Firefox to the main dashboard to start
# We let the agent navigate to the specific Incident/Settings section to test navigation skills
ensure_firefox_on_ela "/event/AppsHome.do#/home/dashboard/0"
sleep 5

# Dismiss any popup dialogs (Escape key)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Create Incident Assignment Rule: 'Critical_Response_Auto'"
echo "   - Severity: Critical"
echo "   - Assign To: admin"
echo "2. Export Technician Audit Trail to '/home/ga/audit_evidence.csv'"