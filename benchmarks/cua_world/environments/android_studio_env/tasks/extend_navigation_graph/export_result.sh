#!/bin/bash
echo "=== Exporting extend_navigation_graph result ==="

source /workspace/scripts/task_utils.sh

# Project configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskTracker"
PACKAGE_PATH="app/src/main/java/com/example/tasktracker"
RES_PATH="app/src/main/res"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
HOME_FRAGMENT_CONTENT=""
SETTINGS_FRAGMENT_CONTENT=""
NAV_GRAPH_CONTENT=""
LAYOUT_CONTENT=""
SETTINGS_FRAGMENT_EXISTS="false"
LAYOUT_EXISTS="false"
BUILD_SUCCESS="false"

# 1. Read HomeFragment.kt
if [ -f "$PROJECT_DIR/$PACKAGE_PATH/HomeFragment.kt" ]; then
    HOME_FRAGMENT_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/HomeFragment.kt")
fi

# 2. Read SettingsFragment.kt
if [ -f "$PROJECT_DIR/$PACKAGE_PATH/SettingsFragment.kt" ]; then
    SETTINGS_FRAGMENT_EXISTS="true"
    SETTINGS_FRAGMENT_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/SettingsFragment.kt")
fi

# 3. Read nav_graph.xml
if [ -f "$PROJECT_DIR/$RES_PATH/navigation/nav_graph.xml" ]; then
    NAV_GRAPH_CONTENT=$(cat "$PROJECT_DIR/$RES_PATH/navigation/nav_graph.xml")
fi

# 4. Read fragment_settings.xml
if [ -f "$PROJECT_DIR/$RES_PATH/layout/fragment_settings.xml" ]; then
    LAYOUT_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$PROJECT_DIR/$RES_PATH/layout/fragment_settings.xml")
fi

# 5. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED_DURING_TASK="false"

if [ "$SETTINGS_FRAGMENT_EXISTS" = "true" ]; then
    FILE_TIME=$(stat -c %Y "$PROJECT_DIR/$PACKAGE_PATH/SettingsFragment.kt" 2>/dev/null || echo "0")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        FILES_MODIFIED_DURING_TASK="true"
    fi
fi

# 6. Attempt Build (Gradle)
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running gradle assembleDebug..."
    cd "$PROJECT_DIR"
    
    # Run build with ga user environment
    su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; \
                export ANDROID_SDK_ROOT=/opt/android-sdk; \
                cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Helper to escape JSON string
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

# Construct JSON result
# Note: We use a temporary python script to safely dump the JSON structure to handle escaping correctly
cat <<EOF > /tmp/construct_result.py
import json

data = {
    "home_fragment_content": $(escape_json "$HOME_FRAGMENT_CONTENT"),
    "settings_fragment_content": $(escape_json "$SETTINGS_FRAGMENT_CONTENT"),
    "nav_graph_content": $(escape_json "$NAV_GRAPH_CONTENT"),
    "layout_content": $(escape_json "$LAYOUT_CONTENT"),
    "settings_fragment_exists": $SETTINGS_FRAGMENT_EXISTS,
    "layout_exists": $LAYOUT_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "files_modified_during_task": $FILES_MODIFIED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
EOF

python3 /tmp/construct_result.py

# Secure the result file
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="