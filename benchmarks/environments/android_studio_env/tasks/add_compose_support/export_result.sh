#!/bin/bash
echo "=== Exporting add_compose_support result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/ViewsApp"
PACKAGE_PATH="app/src/main/java/com/example/viewsapp"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Record Task End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Capture File Contents
# ------------------------

# build.gradle.kts
BUILD_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
fi

# ProfileScreen.kt
PROFILE_SCREEN_CONTENT=""
if [ -f "$PROJECT_DIR/$PACKAGE_PATH/ui/ProfileScreen.kt" ]; then
    PROFILE_SCREEN_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/ui/ProfileScreen.kt")
fi

# ProfileActivity.kt
PROFILE_ACTIVITY_CONTENT=""
if [ -f "$PROJECT_DIR/$PACKAGE_PATH/ProfileActivity.kt" ]; then
    PROFILE_ACTIVITY_CONTENT=$(cat "$PROJECT_DIR/$PACKAGE_PATH/ProfileActivity.kt")
fi

# AndroidManifest.xml
MANIFEST_CONTENT=""
if [ -f "$PROJECT_DIR/app/src/main/AndroidManifest.xml" ]; then
    MANIFEST_CONTENT=$(cat "$PROJECT_DIR/app/src/main/AndroidManifest.xml")
fi

# 4. Verify Build (The Ultimate Test)
# -----------------------------------
# We attempt to build the project. If Compose is configured correctly, this should pass.
# If dependencies are missing or versions mismatch, it will fail.
echo "Running ./gradlew assembleDebug..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

cd "$PROJECT_DIR"
if [ -x "./gradlew" ]; then
    # Use wrapper if available
    GRADLE_CMD="./gradlew"
else
    # Fallback to system gradle
    GRADLE_CMD="gradle"
fi

# Run gradle as ga user
BUILD_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && export ANDROID_SDK_ROOT=/opt/android-sdk && $GRADLE_CMD assembleDebug --no-daemon" 2>&1)
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
fi

# Truncate build output for JSON
BUILD_OUTPUT_SHORT=$(echo "$BUILD_OUTPUT" | tail -n 50)

# 5. Create JSON Result
# ---------------------
# Helper for JSON escaping
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

BUILD_GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
PROFILE_SCREEN_JSON=$(escape_json "$PROFILE_SCREEN_CONTENT")
PROFILE_ACTIVITY_JSON=$(escape_json "$PROFILE_ACTIVITY_CONTENT")
MANIFEST_JSON=$(escape_json "$MANIFEST_CONTENT")
BUILD_OUTPUT_JSON=$(escape_json "$BUILD_OUTPUT_SHORT")

cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_gradle_content": $BUILD_GRADLE_JSON,
    "profile_screen_content": $PROFILE_SCREEN_JSON,
    "profile_activity_content": $PROFILE_ACTIVITY_JSON,
    "manifest_content": $MANIFEST_JSON,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_JSON
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="