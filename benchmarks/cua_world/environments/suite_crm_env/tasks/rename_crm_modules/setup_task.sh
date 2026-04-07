#!/bin/bash
echo "=== Setting up rename_crm_modules task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Ensure logged in and navigate to the Administration page to provide a consistent starting point
echo "Navigating to SuiteCRM Admin page..."
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Administration&action=index"

# Wait a moment for the page to settle
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png

echo "=== rename_crm_modules task setup complete ==="