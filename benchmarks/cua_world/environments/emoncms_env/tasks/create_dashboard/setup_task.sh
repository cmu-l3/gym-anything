#!/bin/bash
# Task setup: create_dashboard
# Navigates to the Dashboards list page so agent can create a new dashboard.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_dashboard task ==="

wait_for_emoncms

APIKEY=$(get_apikey_write)

# Remove "Home Energy Monitor" dashboard if it exists (clean state)
EXISTING=$(db_query "SELECT id FROM dashboard WHERE name='Home Energy Monitor' AND userid=1" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
    curl -s "${EMONCMS_URL}/dashboard/delete?apikey=${APIKEY}&id=${EXISTING}" >/dev/null 2>&1 || true
    echo "Removed existing 'Home Energy Monitor' dashboard (id=${EXISTING})"
fi

# Navigate to Dashboards list page
launch_firefox_to "http://localhost/dashboard/list" 5

# Take a starting screenshot
take_screenshot /tmp/task_create_dashboard_start.png

echo "=== Task setup complete: create_dashboard ==="
