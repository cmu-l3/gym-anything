#!/bin/bash
echo "=== Exporting migrate_groovy_to_kotlin_dsl result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result flags
SETTINGS_KTS_EXISTS="false"
ROOT_BUILD_KTS_EXISTS="false"
APP_BUILD_KTS_EXISTS="false"
GROOVY_FILES_REMOVED="false"
BUILD_SUCCESS="false"

# Check for .gradle.kts files
if [ -f "$PROJECT_DIR/settings.gradle.kts" ]; then SETTINGS_KTS_EXISTS="true"; fi
if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then ROOT_BUILD_KTS_EXISTS="true"; fi
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then APP_BUILD_KTS_EXISTS="true"; fi

# Check if old .gradle files are gone
if [ ! -f "$PROJECT_DIR/settings.gradle" ] && \
   [ ! -f "$PROJECT_DIR/build.gradle" ] && \
   [ ! -f "$PROJECT_DIR/app/build.gradle" ]; then
    GROOVY_FILES_REMOVED="true"
fi

# Try to run Gradle build with the NEW configuration
echo "Running Gradle build to verify conversion..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon 2>&1")
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
fi

# Capture content of KTS files for verification
SETTINGS_CONTENT=""
[ -f "$PROJECT_DIR/settings.gradle.kts" ] && SETTINGS_CONTENT=$(cat "$PROJECT_DIR/settings.gradle.kts")

ROOT_BUILD_CONTENT=""
[ -f "$PROJECT_DIR/build.gradle.kts" ] && ROOT_BUILD_CONTENT=$(cat "$PROJECT_DIR/build.gradle.kts")

APP_BUILD_CONTENT=""
[ -f "$PROJECT_DIR/app/build.gradle.kts" ] && APP_BUILD_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")

# JSON Helper
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

SETTINGS_ESCAPED=$(escape_json "$SETTINGS_CONTENT")
ROOT_BUILD_ESCAPED=$(escape_json "$ROOT_BUILD_CONTENT")
APP_BUILD_ESCAPED=$(escape_json "$APP_BUILD_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# Write result JSON
cat > /tmp/task_result.json << EOF
{
    "settings_kts_exists": $SETTINGS_KTS_EXISTS,
    "root_build_kts_exists": $ROOT_BUILD_KTS_EXISTS,
    "app_build_kts_exists": $APP_BUILD_KTS_EXISTS,
    "groovy_files_removed": $GROOVY_FILES_REMOVED,
    "build_success": $BUILD_SUCCESS,
    "settings_content": $SETTINGS_ESCAPED,
    "root_build_content": $ROOT_BUILD_ESCAPED,
    "app_build_content": $APP_BUILD_ESCAPED,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "task_end_timestamp": $(date +%s)
}
EOF

echo "Result exported to /tmp/task_result.json"