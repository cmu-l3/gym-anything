#!/bin/bash
echo "=== Exporting add_gradle_build_info_task result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"
ASSETS_FILE="$PROJECT_DIR/app/src/main/assets/build-info.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check if build.gradle.kts was modified
BUILD_FILE_MODIFIED="false"
if [ -f "$BUILD_FILE" ]; then
    MOD_TIME=$(stat -c %Y "$BUILD_FILE")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        BUILD_FILE_MODIFIED="true"
    fi
fi

# 2. Capture build.gradle.kts content
BUILD_FILE_CONTENT=""
if [ -f "$BUILD_FILE" ]; then
    BUILD_FILE_CONTENT=$(cat "$BUILD_FILE")
fi

# 3. Test the task execution via Gradle
# This validates that the task definition is syntactically correct and runnable
echo "Running generateBuildInfo task..."
cd "$PROJECT_DIR"
GRADLE_EXIT_CODE=1
GRADLE_OUTPUT=""

# We try to run the task explicitly. 
# This serves two purposes:
# A) Verifies the task exists and runs
# B) Generates the file if the agent forgot to run it (but defined it correctly)
#    (Though the prompt asks them to wire it, we give partial credit if it works manually)
chmod +x gradlew
GRADLE_OUTPUT=$(su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew generateBuildInfo --no-daemon 2>&1")
GRADLE_EXIT_CODE=$?

TASK_RUN_SUCCESS="false"
if [ $GRADLE_EXIT_CODE -eq 0 ]; then
    TASK_RUN_SUCCESS="true"
fi

# 4. Check for task wiring (dependsOn)
# We run a dry-run of preBuild and check if generateBuildInfo is in the plan
echo "Checking task wiring..."
WIRING_OUTPUT=$(su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; ./gradlew preBuild --dry-run 2>&1")
IS_WIRED="false"
if echo "$WIRING_OUTPUT" | grep -q ":app:generateBuildInfo"; then
    IS_WIRED="true"
fi

# 5. Analyze the generated JSON file
JSON_FILE_EXISTS="false"
JSON_CONTENT=""
JSON_FILE_CREATED_DURING_TASK="false"

if [ -f "$ASSETS_FILE" ]; then
    JSON_FILE_EXISTS="true"
    JSON_CONTENT=$(cat "$ASSETS_FILE")
    
    # Check timestamp
    FILE_TIME=$(stat -c %Y "$ASSETS_FILE")
    if [ "$FILE_TIME" -gt "$TASK_START" ]; then
        JSON_FILE_CREATED_DURING_TASK="true"
    fi
fi

# 6. Get Git Hash for verification comparison
GIT_HASH=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "")

# Prepare JSON export using Python to safely escape strings
cat <<EOF > /tmp/export_data.py
import json
import os

data = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "build_file_modified": $BUILD_FILE_MODIFIED,
    "build_file_content": """$BUILD_FILE_CONTENT""",
    "task_run_success": $TASK_RUN_SUCCESS,
    "is_wired": $IS_WIRED,
    "json_file_exists": $JSON_FILE_EXISTS,
    "json_content": """$JSON_CONTENT""",
    "json_created_during_task": $JSON_FILE_CREATED_DURING_TASK,
    "git_hash": "$GIT_HASH",
    "gradle_output": """$GRADLE_OUTPUT"""
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f)
EOF

python3 /tmp/export_data.py
rm -f /tmp/export_data.py

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"