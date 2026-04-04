#!/bin/bash
# Setup for: create_virtual_repo task
echo "=== Setting up create_virtual_repo task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Remove target virtual repo if it already exists (safe in fresh env)
delete_repo_if_exists "generic-virtual"

INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repository count: $INITIAL_REPO_COUNT"

# Show available repositories
echo "Available repositories:"
art_api GET "/api/repositories" | python3 -c "
import sys, json
repos = json.load(sys.stdin)
for r in repos:
    print(f\"  - {r['key']} ({r['type']})\")
" 2>/dev/null || true

ensure_firefox_running "http://localhost:8082"
sleep 2
# Navigate to repository administration
navigate_to "http://localhost:8082/ui/admin/repositories"
sleep 4

take_screenshot /tmp/task_create_virtual_repo_initial.png

echo ""
echo "=== create_virtual_repo Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Administration > Repositories"
echo "  3. Click '+ Add Repositories' > 'Virtual Repository'"
echo "  4. Select Generic as the package type"
echo "  5. Fill in:"
echo "     - Repository Key: generic-virtual"
echo "     - Description: Virtual repository aggregating generic repositories"
echo "  6. In 'Included Repositories', add: example-repo-local"
echo "  7. Click 'Create Virtual Repository'"
echo ""
echo "Pre-existing repos available: example-repo-local (Generic local)"
echo ""
