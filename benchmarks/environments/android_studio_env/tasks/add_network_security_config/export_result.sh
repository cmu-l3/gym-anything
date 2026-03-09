#!/bin/bash
set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
NSC_PATH="$PROJECT_DIR/app/src/main/res/xml/network_security_config.xml"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize Result Variables
NSC_EXISTS="false"
NSC_CONTENT=""
NSC_CREATED_DURING_TASK="false"
MANIFEST_MODIFIED="false"
MANIFEST_CONTENT=""
BUILD_VALID="false"

# 1. Check Network Security Config File
if [ -f "$NSC_PATH" ]; then
    NSC_EXISTS="true"
    NSC_CONTENT=$(cat "$NSC_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$NSC_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        NSC_CREATED_DURING_TASK="true"
    fi
fi

# 2. Check Manifest File
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
    
    # Check if modified since start
    INITIAL_HASH=$(md5sum /tmp/initial_manifest.xml 2>/dev/null | awk '{print $1}')
    CURRENT_HASH=$(md5sum "$MANIFEST_PATH" 2>/dev/null | awk '{print $1}')
    
    if [ "$INITIAL_HASH" != "$CURRENT_HASH" ]; then
        MANIFEST_MODIFIED="true"
    fi
fi

# 3. Quick Build Check (Structural Validity)
# We avoid a full build if possible to save time, but running a lightweight task verifies syntax
echo "Checking build validity..."
if [ -f "$PROJECT_DIR/gradlew" ] && [ "$NSC_EXISTS" = "true" ]; then
    # processDebugResources checks XML validity and manifest linking
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run in background with timeout to prevent hanging the export
    timeout 60s ./gradlew :app:processDebugResources > /tmp/gradle_output.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_VALID="true"
    fi
fi

# Helper for JSON escaping
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

NSC_ESCAPED=$(escape_json "$NSC_CONTENT")
MANIFEST_ESCAPED=$(escape_json "$MANIFEST_CONTENT")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "nsc_exists": $NSC_EXISTS,
    "nsc_created_during_task": $NSC_CREATED_DURING_TASK,
    "nsc_content": $NSC_ESCAPED,
    "manifest_modified": $MANIFEST_MODIFIED,
    "manifest_content": $MANIFEST_ESCAPED,
    "build_valid": $BUILD_VALID,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="