#!/bin/bash
set -e
echo "=== Setting up create_crm_email_template task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for Odoo to be ready
wait_for_odoo

# Record initial template count for anti-gaming
INITIAL_COUNT=$(odoo_db_query "SELECT count(*) FROM mail_template;" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_template_count.txt
echo "Initial mail_template count: $INITIAL_COUNT"

# Ensure Developer Mode is OFF initially to test agent's ability to enable it
# (Clear debug mode from system parameters if set globally, though usually it's session-based)
odoo_db_query "DELETE FROM ir_config_parameter WHERE key='base.debug_mode';" 2>/dev/null || true

# Ensure Firefox is running and logged in, start at CRM pipeline
# This forces the agent to navigate to Settings themselves
ensure_odoo_logged_in "http://localhost:8069/web#action=209&cids=1&menu_id=139"
sleep 3

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || \
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="