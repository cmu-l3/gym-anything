#!/bin/bash
# Setup for: create_group task
echo "=== Setting up create_group task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Remove 'developers' group if it exists (safe in fresh env - won't exist)
delete_group_if_exists "developers"

ensure_firefox_running "http://localhost:8082"
sleep 2
navigate_to "http://localhost:8082/ui/admin/security/groups"
sleep 4

take_screenshot /tmp/task_create_group_initial.png

echo ""
echo "=== create_group Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Administration > Security > Groups"
echo "  3. Click '+ New Group'"
echo "  4. Fill in:"
echo "     - Group Name: developers"
echo "     - Description: Development team with access to release repositories"
echo "  5. Click Save"
echo ""
