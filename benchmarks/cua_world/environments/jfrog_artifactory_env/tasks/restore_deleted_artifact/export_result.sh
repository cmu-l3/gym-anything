#!/bin/bash
echo "=== Exporting Restore Deleted Artifact Result ==="

source /workspace/scripts/task_utils.sh

# Define details
TARGET_URL="${ARTIFACTORY_URL}/artifactory/example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"
RESTORED_FILE="/tmp/restored_artifact.jar"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Artifact Existence (HTTP Status)
echo "Checking if artifact exists..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "${ADMIN_USER}:${ADMIN_PASS}" "$TARGET_URL")
echo "Artifact HTTP Status: $HTTP_CODE"

ARTIFACT_ACCESSIBLE="false"
CHECKSUM_MATCH="false"
SIZE_MATCH="false"
RESTORED_SHA256=""
RESTORED_SIZE="0"

if [ "$HTTP_CODE" = "200" ]; then
    ARTIFACT_ACCESSIBLE="true"
    
    # 2. Download and verify integrity
    echo "Downloading restored artifact for verification..."
    curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" -o "$RESTORED_FILE" "$TARGET_URL"
    
    if [ -f "$RESTORED_FILE" ]; then
        RESTORED_SHA256=$(sha256sum "$RESTORED_FILE" | awk '{print $1}')
        RESTORED_SIZE=$(stat -c %s "$RESTORED_FILE")
        
        EXPECTED_SHA256=$(cat /tmp/expected_sha256.txt 2>/dev/null || echo "")
        EXPECTED_SIZE=$(cat /tmp/expected_size.txt 2>/dev/null || echo "0")
        
        if [ "$RESTORED_SHA256" = "$EXPECTED_SHA256" ]; then
            CHECKSUM_MATCH="true"
        fi
        
        if [ "$RESTORED_SIZE" = "$EXPECTED_SIZE" ]; then
            SIZE_MATCH="true"
        fi
    fi
    
    # 3. Check deployment/creation time (Anti-gaming)
    # Get artifact info JSON
    ARTIFACT_INFO=$(curl -s -u "${ADMIN_USER}:${ADMIN_PASS}" "$TARGET_URL?uploads")
    # Parse 'created' timestamp if possible, otherwise rely on verifier check
fi

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "http_status": $HTTP_CODE,
    "artifact_accessible": $ARTIFACT_ACCESSIBLE,
    "checksum_match": $CHECKSUM_MATCH,
    "size_match": $SIZE_MATCH,
    "restored_sha256": "$RESTORED_SHA256",
    "expected_sha256": "$(cat /tmp/expected_sha256.txt 2>/dev/null)",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to safe location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json