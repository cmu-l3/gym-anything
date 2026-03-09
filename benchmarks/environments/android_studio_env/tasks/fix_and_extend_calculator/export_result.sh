#!/bin/bash
echo "=== Exporting fix_and_extend_calculator result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/CalculatorApp"
PKG_PATH="com/example/calculator"
SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"

take_screenshot /tmp/task_end.png

ACTIVITY_CONTENT=$(cat "$SRC_DIR/CalcActivity.kt" 2>/dev/null)
ENGINE_CONTENT=$(cat "$SRC_DIR/CalcEngine.kt" 2>/dev/null)
LAYOUT_CONTENT=$(cat "$PROJECT_DIR/app/src/main/res/layout/activity_calc.xml" 2>/dev/null)

# Change detection
ACTIVITY_CHANGED="false"
ENGINE_CHANGED="false"
LAYOUT_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$SRC_DIR/CalcActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ACTIVITY_HASH" ] && [ -n "$CURR" ] && ACTIVITY_CHANGED="true"
    CURR=$(md5sum "$SRC_DIR/CalcEngine.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ENGINE_HASH" ] && [ -n "$CURR" ] && ENGINE_CHANGED="true"
    CURR=$(md5sum "$PROJECT_DIR/app/src/main/res/layout/activity_calc.xml" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_LAYOUT_HASH" ] && [ -n "$CURR" ] && LAYOUT_CHANGED="true"
fi

# Build
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

# Escape
ACT_ESC=$(printf '%s' "$ACTIVITY_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ENG_ESC=$(printf '%s' "$ENGINE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LAY_ESC=$(printf '%s' "$LAYOUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BOUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "activity_content": $ACT_ESC,
    "activity_changed": $ACTIVITY_CHANGED,
    "engine_content": $ENG_ESC,
    "engine_changed": $ENGINE_CHANGED,
    "layout_content": $LAY_ESC,
    "layout_changed": $LAYOUT_CHANGED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BOUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
