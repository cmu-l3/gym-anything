#!/bin/bash
echo "=== Setting up Rename Repository Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Wait for Artifactory to be ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory not accessible"
    exit 1
fi

# 2. Clean up environment
echo "Cleaning up repositories..."
delete_repo_if_exists "module-core-local"
delete_repo_if_exists "legacy-dev-local"

# 3. Create the 'legacy-dev-local' repository
echo "Creating source repository 'legacy-dev-local'..."
curl -s -u admin:password -X PUT \
    -H "Content-Type: application/json" \
    -d '{"rclass":"local","packageType":"generic"}' \
    "http://localhost:8082/artifactory/api/repositories/legacy-dev-local"

# 4. Deploy the artifact to 'legacy-dev-local'
ARTIFACT_SOURCE="/home/ga/artifacts/commons-lang3/commons-lang3-3.14.0.jar"
if [ ! -f "$ARTIFACT_SOURCE" ]; then
    # Fallback if specific version missing
    ARTIFACT_SOURCE=$(find /home/ga/artifacts -name "*.jar" | head -n 1)
fi

if [ -f "$ARTIFACT_SOURCE" ]; then
    echo "Deploying artifact to 'legacy-dev-local'..."
    curl -s -u admin:password -X PUT \
        "http://localhost:8082/artifactory/legacy-dev-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar" \
        -T "$ARTIFACT_SOURCE"
else
    echo "ERROR: No artifact file found to deploy"
    exit 1
fi

# 5. Verify Setup
if repo_exists "legacy-dev-local"; then
    echo "Setup successful: legacy-dev-local created."
else
    echo "ERROR: Failed to create legacy-dev-local"
    exit 1
fi

# 6. Open Firefox
echo "Starting Firefox..."
ensure_firefox_running "http://localhost:8082"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="