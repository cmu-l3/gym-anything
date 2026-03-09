#!/bin/bash
set -e
echo "=== Setting up configure_risk_appetite task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

echo "Resetting risk configuration..."

# Reset risk appetites to 3 (Medium) and method to 0 (Simple Threshold)
# This ensures a clean starting state regardless of previous runs
eramba_db_query "UPDATE risk_appetites SET risk_appetite=3, method=0, modified=NOW() WHERE model IN ('Risks', 'ThirdPartyRisks', 'BusinessContinuities');" 2>/dev/null || true

# Ensure risk calculations are set to default 'eramba' method
eramba_db_query "UPDATE risk_calculations SET method='eramba', modified=NOW() WHERE model IN ('Risks', 'ThirdPartyRisks', 'BusinessContinuities');" 2>/dev/null || true

# Log initial state for debugging
INITIAL_STATE=$(eramba_db_query "SELECT model, risk_appetite FROM risk_appetites WHERE model IN ('Risks', 'ThirdPartyRisks', 'BusinessContinuities');" 2>/dev/null)
echo "Initial DB State:"
echo "$INITIAL_STATE"

# Ensure Firefox is running and navigating to Eramba
# We direct to the dashboard so the agent starts from a standard location
ensure_firefox_eramba "http://localhost:8080/dashboard/dashboard"
sleep 5

# Maximize Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true
sleep 1

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="