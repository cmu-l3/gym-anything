#!/bin/bash
echo "=== Exporting Configure ProGuard/R8 Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherNow"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
PROGUARD_RULES="$PROJECT_DIR/app/proguard-rules.pro"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check File Modifications
BUILD_GRADLE_MODIFIED="false"
PROGUARD_MODIFIED="false"

if [ -f "$BUILD_GRADLE" ]; then
    M_TIME=$(stat -c %Y "$BUILD_GRADLE")
    if [ "$M_TIME" -gt "$TASK_START_TIME" ]; then
        BUILD_GRADLE_MODIFIED="true"
    fi
fi

if [ -f "$PROGUARD_RULES" ]; then
    M_TIME=$(stat -c %Y "$PROGUARD_RULES")
    if [ "$M_TIME" -gt "$TASK_START_TIME" ]; then
        PROGUARD_MODIFIED="true"
    fi
fi

# 3. Read File Content
BUILD_GRADLE_CONTENT=""
[ -f "$BUILD_GRADLE" ] && BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")

PROGUARD_CONTENT=""
[ -f "$PROGUARD_RULES" ] && PROGUARD_CONTENT=$(cat "$PROGUARD_RULES")

# 4. Verify Build Success (Attempt assembleRelease)
# We run this to check if the agent's configuration is valid
echo "Running validation build: ./gradlew assembleRelease..."
cd "$PROJECT_DIR"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export ANDROID_SDK_ROOT=/opt/android-sdk

BUILD_SUCCESS="false"
APK_CREATED="false"
APK_SIZE=0

if [ -f "./gradlew" ]; then
    chmod +x ./gradlew
    ./gradlew assembleRelease --no-daemon > /tmp/gradle_build_output.log 2>&1
    BUILD_EXIT_CODE=$?
    
    if [ $BUILD_EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Check for APK
APK_PATH="$PROJECT_DIR/app/build/outputs/apk/release/app-release.apk"
if [ -f "$APK_PATH" ]; then
    APK_CREATED="true"
    APK_SIZE=$(stat -c %s "$APK_PATH")
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

BUILD_GRADLE_ESCAPED=$(escape_json "$BUILD_GRADLE_CONTENT")
PROGUARD_ESCAPED=$(escape_json "$PROGUARD_CONTENT")
BUILD_OUTPUT=$(cat /tmp/gradle_build_output.log 2>/dev/null | tail -n 50)
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# Create Result JSON
cat > /tmp/result_data.json <<EOF
{
  "build_gradle_modified": $BUILD_GRADLE_MODIFIED,
  "proguard_modified": $PROGUARD_MODIFIED,
  "build_gradle_content": $BUILD_GRADLE_ESCAPED,
  "proguard_content": $PROGUARD_ESCAPED,
  "build_success": $BUILD_SUCCESS,
  "apk_created": $APK_CREATED,
  "apk_size": $APK_SIZE,
  "build_output": $BUILD_OUTPUT_ESCAPED
}
EOF

# Move result to expected location
cp /tmp/result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."