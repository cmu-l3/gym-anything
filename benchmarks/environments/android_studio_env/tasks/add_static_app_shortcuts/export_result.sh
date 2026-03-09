#!/bin/bash
echo "=== Exporting add_static_app_shortcuts result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/AndroidStudioProjects/QuickNotes"
SHORTCUTS_XML="$PROJECT_DIR/app/src/main/res/xml/shortcuts.xml"
MANIFEST_XML="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
STRINGS_XML="$PROJECT_DIR/app/src/main/res/values/strings.xml"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Read file contents for verification
SHORTCUTS_CONTENT=""
SHORTCUTS_EXISTS="false"
SHORTCUTS_MTIME="0"
if [ -f "$SHORTCUTS_XML" ]; then
    SHORTCUTS_EXISTS="true"
    SHORTCUTS_CONTENT=$(cat "$SHORTCUTS_XML" 2>/dev/null)
    SHORTCUTS_MTIME=$(stat -c %Y "$SHORTCUTS_XML" 2>/dev/null || echo "0")
fi

MANIFEST_CONTENT=""
MANIFEST_EXISTS="false"
MANIFEST_MTIME="0"
if [ -f "$MANIFEST_XML" ]; then
    MANIFEST_EXISTS="true"
    MANIFEST_CONTENT=$(cat "$MANIFEST_XML" 2>/dev/null)
    MANIFEST_MTIME=$(stat -c %Y "$MANIFEST_XML" 2>/dev/null || echo "0")
fi

STRINGS_CONTENT=""
if [ -f "$STRINGS_XML" ]; then
    STRINGS_CONTENT=$(cat "$STRINGS_XML" 2>/dev/null)
fi

# 2. Check if files were modified during task
SHORTCUTS_MODIFIED="false"
if [ "$SHORTCUTS_MTIME" -gt "$TASK_START" ]; then
    SHORTCUTS_MODIFIED="true"
fi

MANIFEST_MODIFIED="false"
if [ "$MANIFEST_MTIME" -gt "$TASK_START" ]; then
    MANIFEST_MODIFIED="true"
fi

# 3. Attempt to build the project to verify validity
BUILD_SUCCESS="false"
GRADLE_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR" && \
    chmod +x gradlew 2>/dev/null || true
    
    # Run assembleDebug
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    if [ -f /tmp/gradle_output.log ]; then
        GRADLE_OUTPUT=$(tail -50 /tmp/gradle_output.log 2>/dev/null)
    fi
fi

# 4. Check application state
APP_RUNNING=$(pgrep -f "android" > /dev/null && echo "true" || echo "false")

# 5. Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

SHORTCUTS_ESCAPED=$(escape_json "$SHORTCUTS_CONTENT")
MANIFEST_ESCAPED=$(escape_json "$MANIFEST_CONTENT")
STRINGS_ESCAPED=$(escape_json "$STRINGS_CONTENT")
GRADLE_ESCAPED=$(escape_json "$GRADLE_OUTPUT")

# 6. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "shortcuts_exists": $SHORTCUTS_EXISTS,
    "shortcuts_modified": $SHORTCUTS_MODIFIED,
    "manifest_exists": $MANIFEST_EXISTS,
    "manifest_modified": $MANIFEST_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "app_running": $APP_RUNNING,
    "shortcuts_content": $SHORTCUTS_ESCAPED,
    "manifest_content": $MANIFEST_ESCAPED,
    "strings_content": $STRINGS_ESCAPED,
    "gradle_output": $GRADLE_ESCAPED
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="