#!/bin/bash
echo "=== Exporting configure_build_variants result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/CalculatorApp"

take_screenshot /tmp/task_end.png

BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)

# Check for flavor-specific source sets
FREE_RES_EXISTS="false"
FREE_STRINGS_CONTENT=""
if [ -d "$PROJECT_DIR/app/src/free" ]; then
    FREE_RES_EXISTS="true"
    FREE_STRINGS_CONTENT=$(cat "$PROJECT_DIR/app/src/free/res/values/strings.xml" 2>/dev/null)
fi

PREMIUM_RES_EXISTS="false"
PREMIUM_STRINGS_CONTENT=""
if [ -d "$PROJECT_DIR/app/src/premium" ]; then
    PREMIUM_RES_EXISTS="true"
    PREMIUM_STRINGS_CONTENT=$(cat "$PROJECT_DIR/app/src/premium/res/values/strings.xml" 2>/dev/null)
fi

# Build change detection
BUILD_CHANGED="false"
if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR" ] && BUILD_CHANGED="true"
fi

# Try Gradle build
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    # Try freeDebug variant first
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleFreeDebug --no-daemon > /tmp/gradle_output.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    else
        # Fallback to assembleDebug
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
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
BUILD_ESC=$(printf '%s' "$BUILD_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FREE_ESC=$(printf '%s' "$FREE_STRINGS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
PREM_ESC=$(printf '%s' "$PREMIUM_STRINGS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BOUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_gradle_content": $BUILD_ESC,
    "build_gradle_changed": $BUILD_CHANGED,
    "free_res_exists": $FREE_RES_EXISTS,
    "free_strings_content": $FREE_ESC,
    "premium_res_exists": $PREMIUM_RES_EXISTS,
    "premium_strings_content": $PREM_ESC,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BOUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
