#!/bin/bash
# Setup for: tune_remote_repo_cache task
echo "=== Setting up tune_remote_repo_cache task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify Artifactory is accessible
echo "Checking Artifactory connectivity..."
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory is not accessible. Cannot proceed."
    exit 1
fi

# ==============================================================================
# PREPARE REPOSITORY STATE
# We need to ensure 'maven-central-remote' exists and has a cache period != 60.
# We'll set it to 7200 (default) to ensure the agent has to change it.
# ==============================================================================
REPO_KEY="maven-central-remote"
INITIAL_CACHE_VAL=7200

echo "Configuring initial state for $REPO_KEY..."

# Define the repository configuration JSON
# Note: In Artifactory API, creating/updating a repo is a PUT request
# We explicitly set retrievalCachePeriodSecs to 7200
REPO_CONFIG='{
    "key": "'"$REPO_KEY"'",
    "rclass": "remote",
    "packageType": "maven",
    "url": "https://repo1.maven.org/maven2/",
    "retrievalCachePeriodSecs": '"$INITIAL_CACHE_VAL"',
    "description": "Proxy for Maven Central",
    "notes": "Initial setup for cache tuning task"
}'

# Create or Update the repository
# We use the generic art_api function or direct curl
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d "$REPO_CONFIG" \
    "${ARTIFACTORY_URL}/artifactory/api/repositories/${REPO_KEY}")

if [ "$STATUS" == "200" ] || [ "$STATUS" == "201" ]; then
    echo "Successfully configured $REPO_KEY with cache period $INITIAL_CACHE_VAL (HTTP $STATUS)"
else
    echo "ERROR: Failed to configure repository. HTTP $STATUS"
    exit 1
fi

# Verify the initial state via API to be sure
CURRENT_CONFIG=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "${ARTIFACTORY_URL}/artifactory/api/repositories/${REPO_KEY}")
CURRENT_VAL=$(echo "$CURRENT_CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('retrievalCachePeriodSecs', -1))")
echo "Verified initial cache period: $CURRENT_VAL seconds"
echo "$CURRENT_VAL" > /tmp/initial_cache_value.txt

# ==============================================================================
# BROWSER SETUP
# ==============================================================================
echo "Setting up Firefox..."
ensure_firefox_running "${ARTIFACTORY_URL}/ui/admin/repositories/remote"
sleep 5

# Focus Firefox
focus_firefox

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="