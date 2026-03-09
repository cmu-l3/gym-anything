#!/bin/bash
echo "=== Exporting deploy_custom_gav_pom results ==="

source /workspace/scripts/task_utils.sh

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths defined in task
REPO="example-repo-local"
JAR_PATH="com/acme/db/driver/2.5.0/driver-2.5.0.jar"
POM_PATH="com/acme/db/driver/2.5.0/driver-2.5.0.pom"

# 1. Check JAR existence and info
echo "Checking JAR status..."
JAR_INFO=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/storage/$REPO/$JAR_PATH")
JAR_EXISTS=$(echo "$JAR_INFO" | grep -q "\"uri\"" && echo "true" || echo "false")

# 2. Check POM existence and info
echo "Checking POM status..."
POM_INFO=$(curl -s -u admin:password "http://localhost:8082/artifactory/api/storage/$REPO/$POM_PATH")
POM_EXISTS=$(echo "$POM_INFO" | grep -q "\"uri\"" && echo "true" || echo "false")

# 3. Get deployed checksum
DEPLOYED_SHA256=""
if [ "$JAR_EXISTS" = "true" ]; then
    # Extract sha256 from JSON response
    # The storage API returns "checksums": {"sha256": "..."}
    DEPLOYED_SHA256=$(echo "$JAR_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('checksums', {}).get('sha256', ''))" 2>/dev/null || echo "")
fi

# 4. Get source checksum
SOURCE_SHA256=$(cat /tmp/source_checksum.txt 2>/dev/null || echo "source_missing")

# 5. Check creation time (Anti-gaming)
# We want to verify the file was created AFTER task start
CREATED_AFTER_START="false"
if [ "$JAR_EXISTS" = "true" ]; then
    # Parse ISO8601 created time from JSON
    CREATED_STR=$(echo "$JAR_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('created', ''))" 2>/dev/null)
    # Convert to timestamp
    CREATED_TS=$(date -d "$CREATED_STR" +%s 2>/dev/null || echo "0")
    if [ "$CREATED_TS" -gt "$TASK_START" ]; then
        CREATED_AFTER_START="true"
    fi
fi

# 6. Capture final screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "jar_exists": $JAR_EXISTS,
    "pom_exists": $POM_EXISTS,
    "deployed_sha256": "$DEPLOYED_SHA256",
    "source_sha256": "$SOURCE_SHA256",
    "created_during_task": $CREATED_AFTER_START,
    "jar_path_checked": "$JAR_PATH",
    "pom_path_checked": "$POM_PATH"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="