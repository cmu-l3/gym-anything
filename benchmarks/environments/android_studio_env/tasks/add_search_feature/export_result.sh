#!/bin/bash
echo "=== Exporting add_search_feature result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
PKG_PATH="com/google/samples/apps/sunflower"
SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"
RES_DIR="$PROJECT_DIR/app/src/main/res"

take_screenshot /tmp/task_end.png

# Read files
MAIN_CONTENT=$(cat "$SRC_DIR/MainActivity.kt" 2>/dev/null)
LAYOUT_CONTENT=$(cat "$RES_DIR/layout/activity_main.xml" 2>/dev/null)
STRINGS_CONTENT=$(cat "$RES_DIR/values/strings.xml" 2>/dev/null)

# Check for new PlantFilter file
FILTER_CONTENT=""
FILTER_EXISTS="false"
FILTER_FILE=$(find "$SRC_DIR" -name "*[Ff]ilter*" -o -name "*[Ss]earch*" 2>/dev/null | head -1)
if [ -n "$FILTER_FILE" ]; then
    FILTER_EXISTS="true"
    FILTER_CONTENT=$(cat "$FILTER_FILE" 2>/dev/null)
fi

# Check changes
MAIN_CHANGED="false"
LAYOUT_CHANGED="false"
STRINGS_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$SRC_DIR/MainActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_MAIN_HASH" ] && [ -n "$CURR" ] && MAIN_CHANGED="true"
    CURR=$(md5sum "$RES_DIR/layout/activity_main.xml" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_LAYOUT_HASH" ] && [ -n "$CURR" ] && LAYOUT_CHANGED="true"
    CURR=$(md5sum "$RES_DIR/values/strings.xml" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_STRINGS_HASH" ] && [ -n "$CURR" ] && STRINGS_CHANGED="true"
fi

# Build check
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    [ $? -eq 0 ] && BUILD_SUCCESS="true"
    if [ "$BUILD_SUCCESS" = "false" ]; then
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
fi
BUILD_OUTPUT=$(tail -30 /tmp/gradle_output.log 2>/dev/null)

# Write JSON
MAIN_ESC=$(printf '%s' "$MAIN_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LAYOUT_ESC=$(printf '%s' "$LAYOUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
STRINGS_ESC=$(printf '%s' "$STRINGS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FILTER_ESC=$(printf '%s' "$FILTER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "main_content": $MAIN_ESC,
    "main_changed": $MAIN_CHANGED,
    "layout_content": $LAYOUT_ESC,
    "layout_changed": $LAYOUT_CHANGED,
    "strings_content": $STRINGS_ESC,
    "strings_changed": $STRINGS_CHANGED,
    "filter_exists": $FILTER_EXISTS,
    "filter_content": $FILTER_ESC,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
