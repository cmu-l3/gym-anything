#!/bin/bash
echo "=== Exporting implement_biometric_auth result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SecretDiary"
LOGIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/secretdiary/LoginActivity.kt"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Capture File Contents
LOGIN_ACTIVITY_CONTENT=""
if [ -f "$LOGIN_ACTIVITY" ]; then
    LOGIN_ACTIVITY_CONTENT=$(cat "$LOGIN_ACTIVITY")
fi

BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

# 2. Verify Compilation (Gradle Build)
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    # Ensure executable
    chmod +x "$PROJECT_DIR/gradlew"
    
    echo "Running assembleDebug..."
    cd "$PROJECT_DIR"
    
    # Run gradle with timeout and capture output
    # Note: We use || true to prevent script exit on build failure
    OUTPUT=$(su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleDebug --no-daemon" 2>&1) || true
    
    BUILD_OUTPUT="$OUTPUT"
    
    if echo "$OUTPUT" | grep -q "BUILD SUCCESSFUL"; then
        BUILD_SUCCESS="true"
    fi
else
    BUILD_OUTPUT="gradlew not found"
fi

# 3. Escape for JSON
# Python script to safely escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

LOGIN_JSON=$(escape_json "$LOGIN_ACTIVITY_CONTENT")
GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
OUTPUT_JSON=$(escape_json "$BUILD_OUTPUT")

# 4. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "login_activity_content": $LOGIN_JSON,
    "build_gradle_content": $GRADLE_JSON,
    "build_success": $BUILD_SUCCESS,
    "build_output": $OUTPUT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"