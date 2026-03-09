#!/bin/bash
# Setup for: create_local_npm_repo task
echo "=== Setting up create_local_npm_repo task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

# Ensure clean state
delete_repo_if_exists "npm-local"

INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repository count: $INITIAL_REPO_COUNT"

ensure_firefox_running "http://localhost:8082"
sleep 2
navigate_to "http://localhost:8082"
sleep 3

take_screenshot /tmp/task_create_local_npm_repo_initial.png

echo ""
echo "=== create_local_npm_repo Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Administration > Repositories > + Add Repositories > Local Repository"
echo "  3. Select npm as the package type"
echo "  4. Repository Key: npm-local"
echo "  5. Description: Local npm package repository"
echo "  6. Click Create Local Repository"
echo ""
