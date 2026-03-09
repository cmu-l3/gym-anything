#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_PATH="example-repo-local/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar"

# 1. Check if artifact still exists (HEAD request)
echo "Checking artifact existence..."
ARTIFACT_EXISTS="false"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/${TARGET_PATH}")

if [ "$HTTP_CODE" = "200" ]; then
    ARTIFACT_EXISTS="true"
fi

# 2. Fetch Properties JSON
echo "Fetching properties..."
PROPERTIES_JSON="{}"
PROP_HTTP_CODE=$(curl -s -o /tmp/properties_response.json -w "%{http_code}" \
    -u "${ADMIN_USER}:${ADMIN_PASS}" \
    "${ARTIFACTORY_URL}/artifactory/api/storage/${TARGET_PATH}?properties")

if [ "$PROP_HTTP_CODE" = "200" ]; then
    # Cat the content into the variable safely
    PROPERTIES_JSON=$(cat /tmp/properties_response.json)
else
    echo "Properties endpoint returned $PROP_HTTP_CODE"
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "artifact_exists": $ARTIFACT_EXISTS,
    "properties_http_code": "$PROP_HTTP_CODE",
    "properties_data": $PROPERTIES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/properties_response.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="