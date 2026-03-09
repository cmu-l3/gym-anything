#!/bin/bash
# Setup for: set_permission_target task
echo "=== Setting up set_permission_target task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Remove existing permission target if it exists (clean state)
delete_permission_if_exists "public-read"

# Verify example-repo-local exists (always available in Artifactory OSS 7.x)
if repo_exists "example-repo-local"; then
    echo "example-repo-local exists (as expected)"
else
    echo "WARNING: example-repo-local not found - this task depends on it"
fi

ensure_firefox_running "http://localhost:8082"
sleep 2
navigate_to "http://localhost:8082/ui/admin/security/permissions"
sleep 4

take_screenshot /tmp/task_set_permission_target_initial.png

echo ""
echo "=== set_permission_target Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082 (if not already logged in)"
echo "  2. Navigate to Administration > Security > Permissions"
echo "  3. Click '+ New Permission'"
echo "  4. Name: public-read"
echo "  5. In Resources: add repository 'example-repo-local'"
echo "  6. In Users: add 'anonymous' with permission: Read"
echo "  7. Click Save"
echo ""
echo "Purpose: Grant anonymous (unauthenticated) users read access to example-repo-local."
echo ""
