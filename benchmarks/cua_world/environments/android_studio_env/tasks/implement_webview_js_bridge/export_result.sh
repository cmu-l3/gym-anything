#!/bin/bash
set -e
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/HelpCenterApp"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/helpcenterapp/MainActivity.kt"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- Compilation Check ---
echo "Attempting to build project..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    # Run a quick compilation check (assembleDebug)
    # Redirect output to temp file
    if su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build_output.txt 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi

# --- File Content Extraction ---
MAIN_ACTIVITY_CONTENT=""
if [ -f "$MAIN_ACTIVITY" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY")
fi

LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

# Check modification times
MAIN_ACTIVITY_MODIFIED="false"
if [ -f "$MAIN_ACTIVITY" ]; then
    M_TIME=$(stat -c %Y "$MAIN_ACTIVITY")
    if [ "$M_TIME" -gt "$TASK_START" ]; then
        MAIN_ACTIVITY_MODIFIED="true"
    fi
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

ESC_MAIN=$(escape_json "$MAIN_ACTIVITY_CONTENT")
ESC_LAYOUT=$(escape_json "$LAYOUT_CONTENT")

# Create JSON result
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_success": $BUILD_SUCCESS,
    "main_activity_exists": $([ -f "$MAIN_ACTIVITY" ] && echo "true" || echo "false"),
    "layout_exists": $([ -f "$LAYOUT_FILE" ] && echo "true" || echo "false"),
    "main_activity_content": $ESC_MAIN,
    "layout_content": $ESC_LAYOUT,
    "main_activity_modified": $MAIN_ACTIVITY_MODIFIED
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="