#!/bin/bash
# Task setup: create_user
# Removes john_doe if it exists, then opens the admin user management page.

source /workspace/scripts/task_utils.sh

echo "=== Setting up create_user task ==="

wait_for_emoncms

# Remove 'john_doe' user if it exists (clean state)
EXISTING=$(db_query "SELECT id FROM users WHERE username='john_doe'" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms \
        -e "DELETE FROM users WHERE username='john_doe'" 2>/dev/null || true
    echo "Removed existing john_doe user (id=${EXISTING})"
fi

# Navigate to admin user page
launch_firefox_to "http://localhost/admin/users" 5

# Take a starting screenshot
take_screenshot /tmp/task_create_user_start.png

echo "=== Task setup complete: create_user ==="
