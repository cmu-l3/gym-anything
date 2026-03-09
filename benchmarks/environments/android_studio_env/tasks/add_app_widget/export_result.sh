#!/bin/bash
set -e
echo "=== Exporting add_app_widget result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths to expected files
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/widget_weather.xml"
INFO_FILE="$PROJECT_DIR/app/src/main/res/xml/weather_widget_info.xml"
PROVIDER_FILE="$PROJECT_DIR/app/src/main/java/com/example/weatherapp/WeatherWidgetProvider.kt"
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Capture file existence and timestamps
check_file() {
    local path="$1"
    if [ -f "$path" ]; then
        local mtime=$(stat -c %Y "$path")
        local created_during_task="false"
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_during_task="true"
        fi
        echo "true|$created_during_task"
    else
        echo "false|false"
    fi
}

# Read file contents safely
read_file_content() {
    local path="$1"
    if [ -f "$path" ]; then
        cat "$path" 2>/dev/null
    else
        echo ""
    fi
}

LAYOUT_STATUS=$(check_file "$LAYOUT_FILE")
INFO_STATUS=$(check_file "$INFO_FILE")
PROVIDER_STATUS=$(check_file "$PROVIDER_FILE")

LAYOUT_EXISTS=$(echo "$LAYOUT_STATUS" | cut -d'|' -f1)
LAYOUT_NEW=$(echo "$LAYOUT_STATUS" | cut -d'|' -f2)

INFO_EXISTS=$(echo "$INFO_STATUS" | cut -d'|' -f1)
INFO_NEW=$(echo "$INFO_STATUS" | cut -d'|' -f2)

PROVIDER_EXISTS=$(echo "$PROVIDER_STATUS" | cut -d'|' -f1)
PROVIDER_NEW=$(echo "$PROVIDER_STATUS" | cut -d'|' -f2)

# Check Manifest modification
MANIFEST_MODIFIED="false"
if [ -f "$MANIFEST_FILE" ]; then
    CURRENT_HASH=$(md5sum "$MANIFEST_FILE" | awk '{print $1}')
    INITIAL_HASH=$(cat /tmp/initial_manifest_hash.txt | awk '{print $1}' 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
        MANIFEST_MODIFIED="true"
    fi
fi

# Attempt to build the project to verify compilation
echo "Running Gradle build..."
BUILD_SUCCESS="false"
cd "$PROJECT_DIR"
if [ -f "./gradlew" ]; then
    chmod +x ./gradlew
    # Redirect output to log file to avoid buffer issues, capture exit code
    if ./gradlew assembleDebug --no-daemon > /tmp/build_output.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi
BUILD_LOG=$(tail -n 50 /tmp/build_output.log 2>/dev/null || echo "No build log")

# JSON Helper
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

LAYOUT_CONTENT=$(read_file_content "$LAYOUT_FILE")
INFO_CONTENT=$(read_file_content "$INFO_FILE")
PROVIDER_CONTENT=$(read_file_content "$PROVIDER_FILE")
MANIFEST_CONTENT=$(read_file_content "$MANIFEST_FILE")

# Construct JSON
cat > /tmp/task_result.json <<EOF
{
    "layout_exists": $LAYOUT_EXISTS,
    "layout_created_during_task": $LAYOUT_NEW,
    "layout_content": $(escape_json "$LAYOUT_CONTENT"),
    "info_exists": $INFO_EXISTS,
    "info_created_during_task": $INFO_NEW,
    "info_content": $(escape_json "$INFO_CONTENT"),
    "provider_exists": $PROVIDER_EXISTS,
    "provider_created_during_task": $PROVIDER_NEW,
    "provider_content": $(escape_json "$PROVIDER_CONTENT"),
    "manifest_modified": $MANIFEST_MODIFIED,
    "manifest_content": $(escape_json "$MANIFEST_CONTENT"),
    "build_success": $BUILD_SUCCESS,
    "task_start_time": $TASK_START,
    "build_log": $(escape_json "$BUILD_LOG")
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete."