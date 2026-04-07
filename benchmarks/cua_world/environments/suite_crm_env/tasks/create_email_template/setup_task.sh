#!/bin/bash
echo "=== Setting up create_email_template task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial email template count
INITIAL_COUNT=$(suitecrm_db_query "SELECT COUNT(*) FROM email_templates WHERE deleted=0" 2>/dev/null | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_template_count.txt
echo "Initial email template count: $INITIAL_COUNT"

# Clean up any previous task artifacts to ensure a fresh state
suitecrm_db_query "UPDATE email_templates SET deleted=1 WHERE name='Warranty Claim Response'" 2>/dev/null || true

# Ensure Firefox is running and user is logged into SuiteCRM
ensure_suitecrm_logged_in "http://localhost:8000/index.php?module=Home&action=index"

# Wait for page to fully load
sleep 5

# Maximize and focus Firefox (required for UI agents to see the whole application)
focus_firefox
sleep 2

# Take initial state screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "Agent should navigate to Email Templates and create the 'Warranty Claim Response' template."