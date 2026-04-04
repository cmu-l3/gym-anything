#!/bin/bash
echo "=== Exporting add_workmanager_sync result ==="

source /workspace/scripts/task_utils.sh

# Project Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
JAVA_BASE="$PROJECT_DIR/app/src/main/java/com/example/weatherapp"
SYNC_WORKER="$JAVA_BASE/sync/SyncWorker.kt"
APP_CLASS="$JAVA_BASE/WeatherApplication.kt"
MANIFEST="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check File Existence & Read Content
WORKER_EXISTS="false"
WORKER_CONTENT=""
if [ -f "$SYNC_WORKER" ]; then
    WORKER_EXISTS="true"
    WORKER_CONTENT=$(cat "$SYNC_WORKER" 2>/dev/null)
fi

APP_EXISTS="false"
APP_CONTENT=""
if [ -f "$APP_CLASS" ]; then
    APP_EXISTS="true"
    APP_CONTENT=$(cat "$APP_CLASS" 2>/dev/null)
fi

MANIFEST_CONTENT=""
if [ -f "$MANIFEST" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST" 2>/dev/null)
fi

BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE" 2>/dev/null)
elif [ -f "${BUILD_GRADLE%.kts}" ]; then
    # Fallback to Groovy if they deleted .kts
    BUILD_GRADLE_CONTENT=$(cat "${BUILD_GRADLE%.kts}" 2>/dev/null)
fi

# 3. Attempt Build
echo "Attempting Gradle Build..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    chmod +x "$PROJECT_DIR/gradlew"
    cd "$PROJECT_DIR"
    
    # We use assembleDebug to verify compilation
    # Using 'su ga' to ensure environment match
    BUILD_LOG=$(su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug --no-daemon" 2>&1)
    EXIT_CODE=$?
    
    # Capture last 50 lines of log
    BUILD_OUTPUT=$(echo "$BUILD_LOG" | tail -n 50)
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
else
    BUILD_OUTPUT="Gradle wrapper not found"
fi

# 4. JSON Escaping Helper
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

WORKER_ESCAPED=$(escape_json "$WORKER_CONTENT")
APP_ESCAPED=$(escape_json "$APP_CONTENT")
MANIFEST_ESCAPED=$(escape_json "$MANIFEST_CONTENT")
GRADLE_ESCAPED=$(escape_json "$BUILD_GRADLE_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# 5. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "worker_exists": $WORKER_EXISTS,
    "app_exists": $APP_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "worker_content": $WORKER_ESCAPED,
    "app_content": $APP_ESCAPED,
    "manifest_content": $MANIFEST_ESCAPED,
    "build_gradle_content": $GRADLE_ESCAPED,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Safe write
write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="