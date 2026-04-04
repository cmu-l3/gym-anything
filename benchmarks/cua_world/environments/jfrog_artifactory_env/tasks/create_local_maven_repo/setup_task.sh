#!/bin/bash
# Setup for: create_local_maven_repo task
echo "=== Setting up create_local_maven_repo task ==="

source /workspace/scripts/task_utils.sh

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# Remove 'team-releases' if it already exists (ensure clean state)
delete_repo_if_exists "team-releases"

# Record initial repository count for verification
INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repository count: $INITIAL_REPO_COUNT"

# Ensure Firefox is running and navigate to Artifactory
ensure_firefox_running "http://localhost:8082"
sleep 2
navigate_to "http://localhost:8082"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_create_local_maven_repo_initial.png

echo ""
echo "=== create_local_maven_repo Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in to Artifactory: http://localhost:8082"
echo "     - Username: admin"
echo "     - Password: password"
echo ""
echo "  2. Navigate to: Administration > Repositories > Repositories"
echo "     Then click '+ Add Repositories' > 'Local Repository'"
echo ""
echo "  3. Select Maven as the package type"
echo ""
echo "  4. Fill in:"
echo "     - Repository Key: team-releases"
echo "     - Description: Team release artifacts repository"
echo ""
echo "  5. Click 'Create Local Repository'"
echo ""
