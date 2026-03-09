#!/bin/bash
set -e
echo "=== Setting up Migrate Generic to Maven Repo Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory
echo "Waiting for Artifactory..."
wait_for_artifactory 60

# 2. Cleanup target repo if it exists (ensure clean start)
echo "Ensuring target repo 'libs-commons-local' does not exist..."
delete_repo_if_exists "libs-commons-local"

# 3. Create 'temp-uploads' Generic repository
echo "Creating 'temp-uploads' repository..."
# Note: Artifactory OSS API for creating repos might be strict, but generic is usually default or simple.
# If REST API creation fails/is complex, we rely on the fact that we can push to it if it exists,
# or we use a curl command to create it.
# Using the documented API for creating a repository:
REPO_CONFIG_JSON='{
  "key": "temp-uploads",
  "rclass": "local",
  "packageType": "generic",
  "description": "Temporary uploads storage"
}'

curl -u admin:password -X PUT -H "Content-Type: application/json" \
    -d "$REPO_CONFIG_JSON" \
    "http://localhost:8082/artifactory/api/repositories/temp-uploads"

# 4. Populate 'temp-uploads' with artifacts
echo "Populating 'temp-uploads' with Maven artifacts..."
ARTIFACT_DIR="/home/ga/artifacts/commons-lang3"
JAR_FILE="commons-lang3-3.14.0.jar"
POM_FILE="commons-lang3-3.14.0.pom"

# We place them in the standard Maven layout structure inside the Generic repo
# path: org/apache/commons/commons-lang3/3.14.0/
TARGET_PATH="org/apache/commons/commons-lang3/3.14.0"

if [ -f "$ARTIFACT_DIR/$JAR_FILE" ]; then
    echo "Uploading JAR..."
    curl -u admin:password -X PUT -T "$ARTIFACT_DIR/$JAR_FILE" \
        "http://localhost:8082/artifactory/temp-uploads/$TARGET_PATH/$JAR_FILE"
else
    echo "ERROR: Artifact $JAR_FILE not found in $ARTIFACT_DIR"
    exit 1
fi

if [ -f "$ARTIFACT_DIR/$POM_FILE" ]; then
    echo "Uploading POM..."
    curl -u admin:password -X PUT -T "$ARTIFACT_DIR/$POM_FILE" \
        "http://localhost:8082/artifactory/temp-uploads/$TARGET_PATH/$POM_FILE"
fi

# 5. Record Initial State
date +%s > /tmp/task_start_time.txt
# Verify artifacts are there
INITIAL_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u admin:password \
    "http://localhost:8082/artifactory/temp-uploads/$TARGET_PATH/$JAR_FILE")
echo "Initial artifact check: HTTP $INITIAL_CHECK"

if [ "$INITIAL_CHECK" != "200" ] && [ "$INITIAL_CHECK" != "201" ]; then
    echo "WARNING: Failed to populate initial repository properly."
fi

# 6. Prepare Browser
echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082/ui/packages"
sleep 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="