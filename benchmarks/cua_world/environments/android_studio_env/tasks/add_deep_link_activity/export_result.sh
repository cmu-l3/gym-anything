#!/bin/bash
echo "=== Exporting Add Deep Link Activity task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/ShopEasyApp"
ACTIVITY_FILE="$PROJECT_DIR/app/src/main/java/com/example/shopeasy/DeepLinkActivity.kt"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_deep_link.xml"
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Capture file contents if they exist
ACTIVITY_EXISTS="false"
ACTIVITY_CONTENT=""
if [ -f "$ACTIVITY_FILE" ]; then
    ACTIVITY_EXISTS="true"
    ACTIVITY_CONTENT=$(cat "$ACTIVITY_FILE" 2>/dev/null)
fi

LAYOUT_EXISTS="false"
LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE" 2>/dev/null)
fi

MANIFEST_EXISTS="false"
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_FILE" 2>/dev/null)
fi

# 3. Check for Anti-Gaming (File modification time vs Task Start)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED_DURING_TASK="false"
if [ "$ACTIVITY_EXISTS" = "true" ]; then
    ACT_TIME=$(stat -c %Y "$ACTIVITY_FILE" 2>/dev/null || echo "0")
    if [ "$ACT_TIME" -gt "$TASK_START" ]; then
        FILES_MODIFIED_DURING_TASK="true"
    fi
fi

# 4. Check if project builds
# Note: We do a 'check' or 'assembleDebug' to verify compilation
echo "Attempting to build project..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    export ANDROID_SDK_ROOT=/opt/android-sdk
    
    # Run a quick compilation check
    if su - ga -c "cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build_output.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

ESC_ACTIVITY=$(escape_json "$ACTIVITY_CONTENT")
ESC_LAYOUT=$(escape_json "$LAYOUT_CONTENT")
ESC_MANIFEST=$(escape_json "$MANIFEST_CONTENT")

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "activity_exists": $ACTIVITY_EXISTS,
    "layout_exists": $LAYOUT_EXISTS,
    "manifest_exists": $MANIFEST_EXISTS,
    "files_modified_during_task": $FILES_MODIFIED_DURING_TASK,
    "build_success": $BUILD_SUCCESS,
    "activity_content": $ESC_ACTIVITY,
    "layout_content": $ESC_LAYOUT,
    "manifest_content": $ESC_MANIFEST,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/gradle_build_output.log 2>/dev/null || true

echo "Export complete."