#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_REPO="release-libs-local"
SOURCE_REPO="staging-libs-local"
ARTIFACT_PATH="org/apache/commons/commons-lang3/3.14.0"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Function to check artifact in a repo
check_artifact() {
    local repo="$1"
    local filename="$2"
    local url="http://localhost:8082/artifactory/$repo/$ARTIFACT_PATH/$filename"
    local local_dest="/tmp/download_${repo}_${filename}"
    
    # Try to download the file to verify existence and content
    local http_code
    http_code=$(curl -s -o "$local_dest" -w "%{http_code}" -u admin:password "$url")
    
    if [ "$http_code" = "200" ]; then
        local size
        size=$(stat -c%s "$local_dest" 2>/dev/null || echo "0")
        local sha
        sha=$(sha256sum "$local_dest" 2>/dev/null | awk '{print $1}' || echo "")
        
        # Cleanup
        rm -f "$local_dest"
        
        echo "{\"exists\": true, \"size\": $size, \"sha256\": \"$sha\"}"
    else
        echo "{\"exists\": false, \"http_code\": $http_code}"
    fi
}

echo "Verifying JAR in target..."
JAR_TARGET_INFO=$(check_artifact "$TARGET_REPO" "commons-lang3-3.14.0.jar")

echo "Verifying POM in target..."
POM_TARGET_INFO=$(check_artifact "$TARGET_REPO" "commons-lang3-3.14.0.pom")

echo "Verifying JAR in source (should still exist)..."
JAR_SOURCE_INFO=$(check_artifact "$SOURCE_REPO" "commons-lang3-3.14.0.jar")

echo "Verifying POM in source (should still exist)..."
POM_SOURCE_INFO=$(check_artifact "$SOURCE_REPO" "commons-lang3-3.14.0.pom")

# Get original checksums
ORIG_JAR_SHA=$(cat /tmp/source_jar_sha256.txt 2>/dev/null || echo "")
ORIG_POM_SHA=$(cat /tmp/source_pom_sha256.txt 2>/dev/null || echo "")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "target_repo": "$TARGET_REPO",
    "source_repo": "$SOURCE_REPO",
    "original_checksums": {
        "jar": "$ORIG_JAR_SHA",
        "pom": "$ORIG_POM_SHA"
    },
    "target_artifacts": {
        "jar": $JAR_TARGET_INFO,
        "pom": $POM_TARGET_INFO
    },
    "source_artifacts": {
        "jar": $JAR_SOURCE_INFO,
        "pom": $POM_SOURCE_INFO
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json