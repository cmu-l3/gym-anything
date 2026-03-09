#!/bin/bash
echo "=== Exporting convert_maven_to_gradle result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/IdeaProjects/data-utils"

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check 1: File Existence & Timestamps ---
BUILD_GRADLE_EXISTS="false"
SETTINGS_GRADLE_EXISTS="false"
BUILD_GRADLE_CONTENT=""
SETTINGS_GRADLE_CONTENT=""
BUILD_GRADLE_MTIME="0"

if [ -f "$PROJECT_DIR/build.gradle" ]; then
    BUILD_GRADLE_EXISTS="true"
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/build.gradle")
    BUILD_GRADLE_MTIME=$(stat -c %Y "$PROJECT_DIR/build.gradle")
fi

if [ -f "$PROJECT_DIR/settings.gradle" ]; then
    SETTINGS_GRADLE_EXISTS="true"
    SETTINGS_GRADLE_CONTENT=$(cat "$PROJECT_DIR/settings.gradle")
fi

# --- Check 2: Functional Verification (Run Gradle Build) ---
# We use the installed gradle to verify the agent's work
BUILD_SUCCESS="false"
TEST_SUCCESS="false"
JAR_CREATED="false"
BUILD_OUTPUT=""

if [ "$BUILD_GRADLE_EXISTS" = "true" ]; then
    echo "Running gradle build to verify configuration..."
    
    # Run gradle build (compile + test + jar)
    # We use a timeout to prevent hanging if the build is circular/broken
    cd "$PROJECT_DIR"
    
    # Use explicit path to gradle to ensure we use the one we installed
    # Capture output for debugging
    BUILD_OUTPUT=$(timeout 300s /opt/gradle/bin/gradle clean build --no-daemon 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
        TEST_SUCCESS="true" # 'build' includes 'test'
    fi
    
    # Check if JAR was created
    if [ -f "$PROJECT_DIR/build/libs/data-utils-1.0.0.jar" ] || \
       [ -f "$PROJECT_DIR/build/libs/data-utils.jar" ] || \
       [ -n "$(find $PROJECT_DIR/build/libs -name "*.jar" 2>/dev/null)" ]; then
        JAR_CREATED="true"
    fi
fi

# --- Prepare JSON Payload ---

# Escape contents for JSON
BG_ESCAPED=$(echo "$BUILD_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SG_ESCAPED=$(echo "$SETTINGS_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BO_ESCAPED=$(echo "$BUILD_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Calculate anti-gaming metrics
FILE_CREATED_DURING_TASK="false"
if [ "$BUILD_GRADLE_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_gradle_exists": $BUILD_GRADLE_EXISTS,
    "settings_gradle_exists": $SETTINGS_GRADLE_EXISTS,
    "build_gradle_content": $BG_ESCAPED,
    "settings_gradle_content": $SG_ESCAPED,
    "gradle_build_success": $BUILD_SUCCESS,
    "gradle_test_success": $TEST_SUCCESS,
    "jar_created": $JAR_CREATED,
    "build_output_tail": $BO_ESCAPED,
    "file_created_during_task": $FILE_CREATED_DURING_TASK
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="