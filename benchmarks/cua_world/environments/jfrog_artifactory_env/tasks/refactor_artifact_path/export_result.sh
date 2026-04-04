#!/bin/bash
echo "=== Exporting Refactor Artifact Path Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Define verification endpoints
REPO_KEY="example-repo-local"
SOURCE_PATH="misplaced/commons-io-2.15.1.jar"
TARGET_PATH="org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
API_BASE="http://localhost:8082/artifactory/api/storage/${REPO_KEY}"

# 3. Check Source (Should be missing/404)
echo "Checking source path..."
SOURCE_INFO=$(curl -s -u admin:password "${API_BASE}/${SOURCE_PATH}")
# Check if error 404 is in the JSON or header
if echo "$SOURCE_INFO" | grep -q "errors" || echo "$SOURCE_INFO" | grep -q "404"; then
    SOURCE_EXISTS="false"
else
    SOURCE_EXISTS="true"
fi

# 4. Check Target (Should exist)
echo "Checking target path..."
TARGET_INFO=$(curl -s -u admin:password "${API_BASE}/${TARGET_PATH}")
if echo "$TARGET_INFO" | grep -q "downloadUri"; then
    TARGET_EXISTS="true"
    
    # Extract metadata using python for reliability
    TARGET_METADATA=$(echo "$TARGET_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(json.dumps({
        'sha1': data.get('checksums', {}).get('sha1', ''),
        'created': data.get('created', ''),
        'modified': data.get('lastModified', ''),
        'size': data.get('size', 0)
    }))
except:
    print('{}')
")
else
    TARGET_EXISTS="false"
    TARGET_METADATA="{}"
fi

# 5. Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "source_exists": $SOURCE_EXISTS,
    "target_exists": $TARGET_EXISTS,
    "target_metadata": $TARGET_METADATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 7. Save to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="