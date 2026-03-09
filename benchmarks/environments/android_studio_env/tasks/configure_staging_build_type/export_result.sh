#!/bin/bash
echo "=== Exporting configure_staging_build_type result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/Unscramble"
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check if the build file exists
BUILD_FILE_EXISTS="false"
if [ -f "$BUILD_FILE" ]; then
    BUILD_FILE_EXISTS="true"
fi

# 2. Attempt to build the staging variant to verify configuration validity
# We use the Gradle wrapper inside the project
echo "Running ./gradlew assembleStaging..."
BUILD_SUCCESS="false"
APK_CREATED="false"

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    
    # Run the build task and capture output
    # We use 'su - ga' to ensure environment variables (JAVA_HOME etc) are correct
    su - ga -c "cd $PROJECT_DIR && ./gradlew assembleStaging --no-daemon" > /tmp/gradle_build_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build succeeded."
    else
        echo "Build failed."
    fi

    # Check if the APK was actually generated
    if [ -f "$PROJECT_DIR/app/build/outputs/apk/staging/app-staging.apk" ] || \
       [ -f "$PROJECT_DIR/app/build/outputs/apk/staging/app-staging-unsigned.apk" ]; then
        APK_CREATED="true"
        echo "Staging APK found."
    fi
else
    echo "gradlew not found."
fi

# 3. Read Gradle build output for verification logic
GRADLE_OUTPUT=""
if [ -f /tmp/gradle_build_output.log ]; then
    GRADLE_OUTPUT=$(tail -n 50 /tmp/gradle_build_output.log)
fi

# 4. Read build file content for static analysis
BUILD_FILE_CONTENT=""
if [ -f "$BUILD_FILE" ]; then
    BUILD_FILE_CONTENT=$(cat "$BUILD_FILE")
fi

# 5. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ -f "$BUILD_FILE" ]; then
    FILE_MTIME=$(stat -c %Y "$BUILD_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

ESCAPED_CONTENT=$(escape_json "$BUILD_FILE_CONTENT")
ESCAPED_LOG=$(escape_json "$GRADLE_OUTPUT")

# Create JSON result
cat > /tmp/temp_result.json << EOF
{
    "build_file_exists": $BUILD_FILE_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "apk_created": $APK_CREATED,
    "file_modified": $FILE_MODIFIED,
    "build_file_content": $ESCAPED_CONTENT,
    "gradle_log": $ESCAPED_LOG,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
mv /tmp/temp_result.json /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"