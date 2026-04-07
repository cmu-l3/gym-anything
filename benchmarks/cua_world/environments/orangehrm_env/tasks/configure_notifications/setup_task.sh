#!/bin/bash
set -e
echo "=== Setting up configure_notifications task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrangeHRM is running and accessible
wait_for_http "$ORANGEHRM_URL" 60

echo "Resetting email configuration to defaults..."
# Clear existing email configuration
orangehrm_db_query "DELETE FROM ohrm_email_configuration;" 2>/dev/null || true
# Insert default (empty/disabled) configuration if needed by the app, 
# but usually an empty table or specific 'mail_type'='mail' row is default.
# We'll insert a dummy default to ensure a known starting state.
orangehrm_db_query "INSERT INTO ohrm_email_configuration (id, mail_type, sent_as) VALUES (1, 'mail', 'noreply@orangehrm.com');" 2>/dev/null || true

echo "Clearing existing subscribers..."
# Clear existing subscribers to ensure a clean slate
orangehrm_db_query "DELETE FROM ohrm_email_subscriber;" 2>/dev/null || true

# Record the max ID of subscribers (should be 0 now, but good for anti-gaming logic in other contexts)
MAX_SUB_ID=$(orangehrm_db_query "SELECT MAX(id) FROM ohrm_email_subscriber;" 2>/dev/null | tr -d '[:space:]')
echo "${MAX_SUB_ID:-0}" > /tmp/initial_max_sub_id.txt

# Log in and navigate to the Admin Dashboard (or Email Config page directly if preferred, but dashboard is more realistic)
# We'll start at the Admin Dashboard to force navigation.
TARGET_URL="${ORANGEHRM_URL}/web/index.php/admin/viewSystemUser"
ensure_orangehrm_logged_in "$TARGET_URL"

# Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="