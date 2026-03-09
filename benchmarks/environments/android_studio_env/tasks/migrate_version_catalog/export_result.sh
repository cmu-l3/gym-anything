#!/bin/bash
set -e
echo "=== Exporting migrate_version_catalog result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherTracker"
TOML_FILE="$PROJECT_DIR/gradle/libs.versions.toml"
APP_BUILD="$PROJECT_DIR/app/build.gradle.kts"
DATA_BUILD="$PROJECT_DIR/data/build.gradle.kts"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check build status
echo "Running Gradle build to verify correctness..."
BUILD_SUCCESS="false"
BUILD_OUTPUT_LOG="/tmp/gradle_build_verify.log"

# We use 'assembleDebug' to verify the build configuration is valid
# Using su - ga to run as the user
if su - ga -c "cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > "$BUILD_OUTPUT_LOG" 2>&1; then
    BUILD_SUCCESS="true"
    echo "Build succeeded."
else
    echo "Build failed."
fi

# 3. Capture file contents
TOML_CONTENT=""
TOML_EXISTS="false"
if [ -f "$TOML_FILE" ]; then
    TOML_EXISTS="true"
    TOML_CONTENT=$(cat "$TOML_FILE" 2>/dev/null)
fi

APP_BUILD_CONTENT=""
if [ -f "$APP_BUILD" ]; then
    APP_BUILD_CONTENT=$(cat "$APP_BUILD" 2>/dev/null)
fi

DATA_BUILD_CONTENT=""
if [ -f "$DATA_BUILD" ]; then
    DATA_BUILD_CONTENT=$(cat "$DATA_BUILD" 2>/dev/null)
fi

# 4. Check modification timestamps vs task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TOML_MTIME=$(stat -c %Y "$TOML_FILE" 2>/dev/null || echo "0")
APP_MTIME=$(stat -c %Y "$APP_BUILD" 2>/dev/null || echo "0")
DATA_MTIME=$(stat -c %Y "$DATA_BUILD" 2>/dev/null || echo "0")

FILES_MODIFIED_DURING_TASK="false"
if [ "$TOML_MTIME" -gt "$TASK_START" ] || \
   ( [ "$APP_MTIME" -gt "$TASK_START" ] && [ "$DATA_MTIME" -gt "$TASK_START" ] ); then
    FILES_MODIFIED_DURING_TASK="true"
fi

# 5. Check hash changes
APP_HASH_CHANGED="false"
DATA_HASH_CHANGED="false"

CURRENT_APP_HASH=$(md5sum "$APP_BUILD" 2>/dev/null | awk '{print $1}')
INITIAL_APP_HASH=$(cat /tmp/initial_app_build_hash.txt 2>/dev/null | awk '{print $1}')

if [ "$CURRENT_APP_HASH" != "$INITIAL_APP_HASH" ]; then
    APP_HASH_CHANGED="true"
fi

CURRENT_DATA_HASH=$(md5sum "$DATA_BUILD" 2>/dev/null | awk '{print $1}')
INITIAL_DATA_HASH=$(cat /tmp/initial_data_build_hash.txt 2>/dev/null | awk '{print $1}')

if [ "$CURRENT_DATA_HASH" != "$INITIAL_DATA_HASH" ]; then
    DATA_HASH_CHANGED="true"
fi

# 6. JSON Export
# Use python for safe JSON encoding
cat <<EOF | python3 > /tmp/task_result.json
import json
import os

result = {
    "build_success": $BUILD_SUCCESS,
    "toml_exists": $TOML_EXISTS,
    "toml_content": """$TOML_CONTENT""",
    "app_build_content": """$APP_BUILD_CONTENT""",
    "data_build_content": """$DATA_BUILD_CONTENT""",
    "files_modified_during_task": $FILES_MODIFIED_DURING_TASK,
    "app_hash_changed": $APP_HASH_CHANGED,
    "data_hash_changed": $DATA_HASH_CHANGED,
    "screenshot_path": "/tmp/task_final.png"
}
print(json.dumps(result))
EOF

# Permission fix
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="