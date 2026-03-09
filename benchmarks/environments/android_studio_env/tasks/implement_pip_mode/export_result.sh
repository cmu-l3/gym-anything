#!/bin/bash
echo "=== Exporting implement_pip_mode results ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/StreamFlix"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
ACTIVITY_PATH="$PROJECT_DIR/app/src/main/java/com/example/streamflix/PlayerActivity.kt"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Read file contents
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

ACTIVITY_CONTENT=""
if [ -f "$ACTIVITY_PATH" ]; then
    ACTIVITY_CONTENT=$(cat "$ACTIVITY_PATH")
fi

# 2. Check for modification (Anti-gaming)
MANIFEST_MODIFIED="false"
ACTIVITY_MODIFIED="false"

if [ -f "$MANIFEST_PATH" ] && [ -f /tmp/manifest_initial_hash ]; then
    CURRENT_HASH=$(md5sum "$MANIFEST_PATH" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/manifest_initial_hash | awk '{print $1}')
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        MANIFEST_MODIFIED="true"
    fi
fi

if [ -f "$ACTIVITY_PATH" ] && [ -f /tmp/activity_initial_hash ]; then
    CURRENT_HASH=$(md5sum "$ACTIVITY_PATH" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/activity_initial_hash | awk '{print $1}')
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        ACTIVITY_MODIFIED="true"
    fi
fi

# 3. Verify Build
BUILD_SUCCESS="false"
if [ "$MANIFEST_MODIFIED" = "true" ] || [ "$ACTIVITY_MODIFIED" = "true" ]; then
    echo "Files modified, attempting build verification..."
    cd "$PROJECT_DIR"
    if su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew assembleDebug --no-daemon" > /tmp/build_output.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
else
    echo "No modifications detected, skipping build."
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

MANIFEST_ESCAPED=$(escape_json "$MANIFEST_CONTENT")
ACTIVITY_ESCAPED=$(escape_json "$ACTIVITY_CONTENT")

# Create JSON result
cat > /tmp/result_gen.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "manifest_modified": $MANIFEST_MODIFIED,
    "activity_modified": $ACTIVITY_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "manifest_content": $MANIFEST_ESCAPED,
    "activity_content": $ACTIVITY_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result_gen.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."