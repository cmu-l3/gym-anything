#!/bin/bash
echo "=== Exporting implement_scoped_storage_save result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/PhotoStamp"
TARGET_FILE="$PROJECT_DIR/app/src/main/java/com/example/photostamp/ImageExporter.kt"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check if file exists and read content
FILE_EXISTS="false"
FILE_CONTENT=""

if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$TARGET_FILE")
fi

# 3. Attempt to build the project to verify compilation
# We only compile the debug sources to save time
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle build..."
    cd "$PROJECT_DIR"
    
    # Ensure gradlew is executable
    chmod +x gradlew
    
    # Run compilation (not full assemble to be faster, but verify code validity)
    # Using 'compileDebugKotlin' is usually sufficient to check syntax and type errors
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_build.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Capture last 50 lines of log
    BUILD_OUTPUT=$(tail -n 50 /tmp/gradle_build.log)
fi

# 4. Prepare JSON result
# Use python to safely escape strings for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

ESCAPED_CONTENT=$(escape_json "$FILE_CONTENT")
ESCAPED_LOG=$(escape_json "$BUILD_OUTPUT")

cat > /tmp/task_result.json <<EOF
{
    "file_exists": $FILE_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "file_content": $ESCAPED_CONTENT,
    "build_log": $ESCAPED_LOG,
    "timestamp": $(date +%s)
}
EOF

echo "Result exported to /tmp/task_result.json"