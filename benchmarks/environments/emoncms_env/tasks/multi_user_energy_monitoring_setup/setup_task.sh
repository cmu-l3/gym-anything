#!/bin/bash
echo "=== Setting up multi_user_energy_monitoring_setup ==="
source /workspace/scripts/task_utils.sh

wait_for_emoncms

# Remove any existing tenant_a / tenant_b users (clean slate)
echo "Removing any existing tenant accounts..."
for username in tenant_a tenant_b; do
    USER_ID=$(db_query "SELECT id FROM users WHERE username='${username}'" 2>/dev/null | head -1)
    if [ -n "$USER_ID" ]; then
        # Remove their feeds, inputs, and dashboards before deleting user
        db_query "DELETE FROM feeds WHERE userid=${USER_ID}" 2>/dev/null || true
        db_query "DELETE FROM input WHERE userid=${USER_ID}" 2>/dev/null || true
        db_query "DELETE FROM dashboard WHERE userid=${USER_ID}" 2>/dev/null || true
        db_query "DELETE FROM users WHERE id=${USER_ID}" 2>/dev/null || true
        echo "Removed existing user '${username}' (id=${USER_ID})"
    fi
done

# Record baseline (number of non-admin users)
INITIAL_USER_COUNT=$(db_query "SELECT COUNT(*) FROM users WHERE username != 'admin'" 2>/dev/null | head -1)
echo "${INITIAL_USER_COUNT:-0}" > /tmp/initial_user_count

date +%s > /tmp/task_start_timestamp

# Navigate to admin user management page
launch_firefox_to "http://localhost/user/list" 5

take_screenshot /tmp/task_multiuser_start.png

echo "=== Setup complete: multi_user_energy_monitoring_setup ==="
echo "No tenant accounts exist — agent must create tenant_a and tenant_b"
echo "Agent must use each tenant's API key to post data and configure feeds"
