#!/bin/bash
# Setup for: add_user task
echo "=== Setting up add_user task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Remove john_doe if exists (clean state)
delete_user_if_exists "john_doe"

INITIAL_USER_COUNT=$(get_user_count)
echo "$INITIAL_USER_COUNT" > /tmp/initial_user_count
echo "Initial user count: $INITIAL_USER_COUNT"

ensure_firefox_running "http://localhost:8082"
sleep 2
# Navigate directly to the users admin page
navigate_to "http://localhost:8082/ui/admin/security/users"
sleep 4

take_screenshot /tmp/task_add_user_initial.png

echo ""
echo "=== add_user Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Administration > Security > Users"
echo "  3. Click '+ New User' (or 'Add User')"
echo "  4. Fill in:"
echo "     - Username: john_doe"
echo "     - Email: john.doe@company.com"
echo "     - Password: JohnDoe@123"
echo "     - Keep 'Admin' unchecked"
echo "  5. Click Save"
echo ""
