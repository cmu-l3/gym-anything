#!/bin/bash
echo "=== Setting up configure_virtual_deploy_target task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory to be ready
echo "Waiting for Artifactory..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time."
    exit 1
fi

# 2. Ensure 'example-repo-local' exists (it's standard, but let's be safe)
# In OSS, we can't easily create via API if missing without Pro features sometimes,
# but setup_artifactory.sh checks for it. We'll assume it exists or fail.
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local missing. Attempting to create..."
    # Try creating it (best effort for OSS)
    art_api PUT "/api/repositories/example-repo-local" \
    '{ "key": "example-repo-local", "rclass": "local", "packageType": "maven", "description": "Example local repo" }' \
    -H "Content-Type: application/json"
fi

# 3. Create/Reset 'libs-virtual' with NO default deployment repo
echo "Configuring initial state for libs-virtual..."
# We use PUT to create or overwrite. 
# Content-Type specific for virtual repos is often required or safe to use json.
curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -X PUT "${ARTIFACTORY_URL}/artifactory/api/repositories/libs-virtual" \
    -H "Content-Type: application/vnd.org.jfrog.artifactory.repositories.VirtualRepositoryConfiguration+json" \
    -d '{
    "key": "libs-virtual",
    "rclass": "virtual",
    "packageType": "maven",
    "repositories": ["example-repo-local"],
    "description": "Virtual repository for libraries",
    "defaultDeploymentRepo": ""
}' > /dev/null

# Verify setup
INITIAL_CONFIG=$(get_repo_info "libs-virtual")
echo "Initial config state: $(echo "$INITIAL_CONFIG" | jq -r '.defaultDeploymentRepo // "None"')"

# 4. Prepare Browser
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082/ui/admin/repositories/repositories"

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="