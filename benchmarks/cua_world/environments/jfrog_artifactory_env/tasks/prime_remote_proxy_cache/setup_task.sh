#!/bin/bash
# Setup for prime_remote_proxy_cache task
echo "=== Setting up prime_remote_proxy_cache task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory to be ready
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi
echo "Artifactory is accessible."

# 2. Ensure clean state: Delete the repo if it exists
REPO_KEY="central-proxy-test"
echo "Ensuring repository '$REPO_KEY' does not exist..."
delete_repo_if_exists "$REPO_KEY"

# 3. Ensure the artifact is not cached in any other likely cache locations 
# (though specific to the new repo, cleaning broadly is safer)
# Note: In OSS we can't easily delete generic cache items without ID, 
# but deleting the repo above handles the specific cache for that repo.

# 4. Launch Firefox and login
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5

# 5. Navigate to Administration page to save agent time
navigate_to "http://localhost:8082/ui/admin/repositories/repositories"
sleep 2

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Instructions:"
echo "1. Create Remote Maven Repository 'central-proxy-test' -> 'https://repo1.maven.org/maven2/'"
echo "2. Request/Download 'commons-collections4-4.4.jar' through this repo to prime the cache"