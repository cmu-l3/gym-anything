#!/bin/bash
echo "=== Exporting implement_retrofit_with_error_handling result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/CryptoTrackerApp"
PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/cryptotracker"

take_screenshot /tmp/task_end.png

# Read key source files
BUILD_GRADLE=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
MANIFEST=$(cat "$PROJECT_DIR/app/src/main/AndroidManifest.xml" 2>/dev/null)
ACTIVITY=$(cat "$PKG_DIR/ui/CryptoListActivity.kt" 2>/dev/null)

# Look for network files (may be named differently or in network/ subfolder)
API_FILE=$(find "$PKG_DIR" -name "*.kt" -exec grep -l "@GET\|interface.*Api" {} \; 2>/dev/null | head -1)
API_CONTENT=$(cat "$API_FILE" 2>/dev/null)

CLIENT_FILE=$(find "$PKG_DIR" -name "*.kt" -exec grep -l "OkHttpClient\|Retrofit.Builder\|ApiClient" {} \; 2>/dev/null | head -1)
CLIENT_CONTENT=$(cat "$CLIENT_FILE" 2>/dev/null)

DTO_FILE=$(find "$PKG_DIR" -name "*.kt" -exec grep -l "@SerializedName\|SerializedName" {} \; 2>/dev/null | head -1)
DTO_CONTENT=$(cat "$DTO_FILE" 2>/dev/null)

# Change detection
BUILD_CHANGED="false"
MANIFEST_CHANGED="false"
ACTIVITY_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR" ] && BUILD_CHANGED="true"
    CURR=$(md5sum "$PROJECT_DIR/app/src/main/AndroidManifest.xml" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_MANIFEST_HASH" ] && [ -n "$CURR" ] && MANIFEST_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/CryptoListActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ACTIVITY_HASH" ] && [ -n "$CURR" ] && ACTIVITY_CHANGED="true"
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
        ./gradlew compileDebugKotlin --no-daemon >> /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
fi
BUILD_OUTPUT=$(tail -40 /tmp/gradle_output.log 2>/dev/null)

# Escape for JSON
BUILD_ESC=$(printf '%s' "$BUILD_GRADLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MANIFEST_ESC=$(printf '%s' "$MANIFEST" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ACTIVITY_ESC=$(printf '%s' "$ACTIVITY" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
API_ESC=$(printf '%s' "$API_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CLIENT_ESC=$(printf '%s' "$CLIENT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
DTO_ESC=$(printf '%s' "$DTO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
API_PATH_ESC=$(printf '%s' "${API_FILE:-}" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
CLIENT_PATH_ESC=$(printf '%s' "${CLIENT_FILE:-}" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_gradle_content": $BUILD_ESC,
    "build_gradle_changed": $BUILD_CHANGED,
    "manifest_content": $MANIFEST_ESC,
    "manifest_changed": $MANIFEST_CHANGED,
    "activity_content": $ACTIVITY_ESC,
    "activity_changed": $ACTIVITY_CHANGED,
    "api_interface_content": $API_ESC,
    "api_interface_path": $API_PATH_ESC,
    "api_client_content": $CLIENT_ESC,
    "api_client_path": $CLIENT_PATH_ESC,
    "dto_content": $DTO_ESC,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
