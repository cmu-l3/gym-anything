#!/bin/bash
# Setup for: create_remote_repo task
echo "=== Setting up create_remote_repo task ==="

source /workspace/scripts/task_utils.sh

echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory is not accessible."
    exit 1
fi

delete_repo_if_exists "maven-central-proxy"

INITIAL_REPO_COUNT=$(get_repo_count)
echo "$INITIAL_REPO_COUNT" > /tmp/initial_repo_count
echo "Initial repository count: $INITIAL_REPO_COUNT"

ensure_firefox_running "http://localhost:8082"
sleep 2
navigate_to "http://localhost:8082"
sleep 3

take_screenshot /tmp/task_create_remote_repo_initial.png

echo ""
echo "=== create_remote_repo Task Setup Complete ==="
echo ""
echo "Task Instructions:"
echo "  1. Log in: admin / password at http://localhost:8082"
echo "  2. Navigate to Administration > Repositories > + Add Repositories > Remote Repository"
echo "  3. Select Maven as the package type"
echo "  4. Repository Key: maven-central-proxy"
echo "  5. Remote Repository URL: https://repo1.maven.org/maven2"
echo "  6. Description: Proxy for Maven Central Repository"
echo "  7. Click Create Remote Repository"
echo ""
