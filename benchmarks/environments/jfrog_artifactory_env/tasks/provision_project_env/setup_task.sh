#!/bin/bash
set -e
echo "=== Setting up Provision Project Env Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Artifactory is ready
if ! wait_for_artifactory 60; then
    echo "ERROR: Artifactory not accessible"
    exit 1
fi

# 3. Clean up any existing entities to ensure a fresh start
#    We use the API to delete them if they exist from a previous run
echo "Cleaning up stale entities..."

# Delete Permission Target
curl -s -u admin:password -X DELETE "http://localhost:8082/artifactory/api/security/permissions/alpha-access" > /dev/null || true

# Delete User
curl -s -u admin:password -X DELETE "http://localhost:8082/artifactory/api/security/users/alpha-lead" > /dev/null || true

# Delete Group
curl -s -u admin:password -X DELETE "http://localhost:8082/artifactory/api/security/groups/alpha-team" > /dev/null || true

# Delete Repository
curl -s -u admin:password -X DELETE "http://localhost:8082/artifactory/api/repositories/alpha-local" > /dev/null || true

# 4. Record initial counts (optional, for debugging)
get_repo_count > /tmp/initial_repo_count.txt
get_user_count > /tmp/initial_user_count.txt

# 5. Launch Firefox and prepare UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5

# Navigate to Admin dashboard to save agent time
navigate_to "http://localhost:8082/ui/admin"

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="