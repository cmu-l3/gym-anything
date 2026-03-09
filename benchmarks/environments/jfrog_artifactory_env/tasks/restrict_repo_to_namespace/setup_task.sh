#!/bin/bash
set -e
echo "=== Setting up Restrict Repo to Namespace task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time
date +%s > /tmp/task_start_time.txt

# 2. Ensure Artifactory is ready
echo "Waiting for Artifactory..."
wait_for_artifactory 120

# 3. Ensure 'example-repo-local' exists and reset its state
# In OSS, we might not be able to create/update via API easily if Pro-only,
# but we can try to ensure it's in a clean state if possible.
# Since we can't easily PATCH the repo in OSS via API (often restricted),
# we rely on the fact that it's the default repo.
# We will check if it exists in the list.
if ! repo_exists "example-repo-local"; then
    echo "WARNING: example-repo-local not found. Attempting to create or wait..."
    # If strictly OSS, we might be stuck if it's missing, but setup_artifactory.sh 
    # guarantees it for this environment.
fi

# 4. Start Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"

# 5. Navigate to login or home
navigate_to "http://localhost:8082/ui/login"
sleep 5

# 6. Capture initial state
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="