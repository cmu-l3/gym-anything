#!/bin/bash
# Setup script for configure_billing_profile_fields task
echo "=== Setting up configure_billing_profile_fields ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure services are running
ensure_services_running 120

# 2. Reset/Clean state (if needed)
# In a real scenario we might want to ensure the field doesn't already exist from a previous run
# but since the VM usually resets or we use unique IDs, we'll just record the start time.
# However, if the field exists, we should probably delete it to make the task valid.
echo "Cleaning up potential stale configuration..."
cd /var/www/html/drupal
$DRUSH config:delete field.field.profile.customer.field_contact_phone -y 2>/dev/null || true
$DRUSH config:delete field.storage.profile.field_contact_phone -y 2>/dev/null || true

# Reset profile label if it was changed
# We can't easily revert the label without a full config import, but we can set it via Drush if needed.
# For now, we assume a clean environment or acceptable state.

# 3. Record task start time
date +%s > /tmp/task_start_timestamp

# 4. Navigate Firefox to the Profile Types page to help the agent start
# Path: /admin/config/people/profile-types
echo "Navigating to Profile Types configuration..."
navigate_firefox_to "http://localhost/admin/config/people/profile-types"
sleep 5

# 5. Focus and maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="