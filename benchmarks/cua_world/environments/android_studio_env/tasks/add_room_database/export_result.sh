#!/bin/bash
set -e

echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskTracker"
DATA_PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/tasktracker/data"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result variables
PROJECT_BUILD_CONTENT=""
APP_BUILD_CONTENT=""
TASK_KT_CONTENT=""
TASK_DAO_CONTENT=""
DB_CONTENT=""

# Read files (handling potential missing files)
if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    PROJECT_BUILD_CONTENT=$(cat "$PROJECT_DIR/build.gradle.kts")
fi

if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    APP_BUILD_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
fi

if [ -f "$DATA_PKG_DIR/Task.kt" ]; then
    TASK_KT_CONTENT=$(cat "$DATA_PKG_DIR/Task.kt")
elif [ -f "$PROJECT_DIR/app/src/main/java/com/example/tasktracker/Task.kt" ]; then
    # Fallback location check
    TASK_KT_CONTENT=$(cat "$PROJECT_DIR/app/src/main/java/com/example/tasktracker/Task.kt")
fi

if [ -f "$DATA_PKG_DIR/TaskDao.kt" ]; then
    TASK_DAO_CONTENT=$(cat "$DATA_PKG_DIR/TaskDao.kt")
fi

if [ -f "$DATA_PKG_DIR/AppDatabase.kt" ]; then
    DB_CONTENT=$(cat "$DATA_PKG_DIR/AppDatabase.kt")
fi

# Attempt to build to verify compilation
BUILD_SUCCESS="false"
echo "Running Gradle build check..."
cd "$PROJECT_DIR"
# Use ./gradlew assembleDebug
if [ -f "./gradlew" ]; then
    # Set environment variables for headless build
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    export ANDROID_SDK_ROOT=/opt/android-sdk
    
    # We run 'assembleDebug' to verify it builds
    # Capture output to log
    set +e
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_result.log 2>&1
    EXIT_CODE=$?
    set -e
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build succeeded"
    else
        echo "Build failed (Exit code: $EXIT_CODE)"
    fi
else
    echo "Gradle wrapper not found"
fi

# Helper for JSON escaping
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

# Construct JSON result
# We use Python to construct the JSON to avoid escaping hell in bash
python3 -c "
import json
import os

result = {
    'project_build_gradle': '''$PROJECT_BUILD_CONTENT''',
    'app_build_gradle': '''$APP_BUILD_CONTENT''',
    'task_kt': '''$TASK_KT_CONTENT''',
    'task_dao_kt': '''$TASK_DAO_CONTENT''',
    'database_kt': '''$DB_CONTENT''',
    'build_success': $BUILD_SUCCESS,
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle file permissions
chmod 666 /tmp/task_result.json

echo "Results exported to /tmp/task_result.json"