#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up assign_user_to_group task ==="
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory to be ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not ready"
    exit 1
fi

# 2. clean up previous state
echo "Cleaning up..."
delete_user_if_exists "dev-maria"
delete_group_if_exists "release-engineers"
sleep 2

# 3. Create the Group (empty)
echo "Creating group 'release-engineers'..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT \
    -H "Content-Type: application/json" \
    -d '{"name":"release-engineers","description":"Release Engineering Team","autoJoin":false}' \
    "${ARTIFACTORY_URL}/artifactory/api/security/groups/release-engineers" > /dev/null

# 4. Create the User (no groups)
echo "Creating user 'dev-maria'..."
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT \
    -H "Content-Type: application/json" \
    -d '{"name":"dev-maria","email":"maria@devteam.io","password":"DevMaria2024!","admin":false,"profileUpdatable":true,"groups":[]}' \
    "${ARTIFACTORY_URL}/artifactory/api/security/users/dev-maria" > /dev/null

# 5. Record initial state for anti-gaming
echo "Recording initial state..."
INITIAL_GROUP_INFO=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" \
  "${ARTIFACTORY_URL}/artifactory/api/security/groups/release-engineers?includeUsers=true" 2>/dev/null || echo "{}")
echo "$INITIAL_GROUP_INFO" > /tmp/initial_group_state.json

# 6. Prepare UI
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/security/groups" 
sleep 5
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="