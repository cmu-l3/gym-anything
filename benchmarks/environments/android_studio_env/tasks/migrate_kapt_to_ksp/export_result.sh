#!/bin/bash
echo "=== Exporting migrate_kapt_to_ksp result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/NoteApp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Read Build Files
echo "Reading build files..."
PROJECT_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    PROJECT_GRADLE_CONTENT=$(cat "$PROJECT_DIR/build.gradle.kts")
fi

APP_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    APP_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
fi

# 2. Check File Modification Times (Anti-gaming)
FILES_MODIFIED="false"
PROJECT_GRADLE_MTIME=$(stat -c %Y "$PROJECT_DIR/build.gradle.kts" 2>/dev/null || echo "0")
APP_GRADLE_MTIME=$(stat -c %Y "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null || echo "0")

if [ "$PROJECT_GRADLE_MTIME" -gt "$TASK_START" ] || [ "$APP_GRADLE_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 3. Check Checksums (Anti-gaming)
CHECKSUMS_CHANGED="false"
CURRENT_PROJECT_SUM=$(md5sum "$PROJECT_DIR/build.gradle.kts" 2>/dev/null | awk '{print $1}')
CURRENT_APP_SUM=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
INITIAL_PROJECT_SUM=$(cat /tmp/initial_build_gradle_checksum.txt 2>/dev/null | awk '{print $1}')
INITIAL_APP_SUM=$(cat /tmp/initial_app_build_gradle_checksum.txt 2>/dev/null | awk '{print $1}')

if [ "$CURRENT_PROJECT_SUM" != "$INITIAL_PROJECT_SUM" ] || [ "$CURRENT_APP_SUM" != "$INITIAL_APP_SUM" ]; then
    CHECKSUMS_CHANGED="true"
fi

# 4. Verify Build Success
echo "Running build verification..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""
KAPT_TASKS_RAN="false"
KSP_TASKS_RAN="false"

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    
    # We use 'clean' to ensure we aren't using cached artifacts from the initial setup
    # We use 'assembleDebug' to trigger the full annotation processing
    BUILD_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew clean assembleDebug --no-daemon 2>&1")
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Check if KAPT or KSP tasks ran
    if echo "$BUILD_OUTPUT" | grep -q "kaptGenerateStubs"; then
        KAPT_TASKS_RAN="true"
    fi
    if echo "$BUILD_OUTPUT" | grep -q "kspDebugKotlin"; then
        KSP_TASKS_RAN="true"
    fi
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

PROJECT_GRADLE_ESCAPED=$(escape_json "$PROJECT_GRADLE_CONTENT")
APP_GRADLE_ESCAPED=$(escape_json "$APP_GRADLE_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "project_gradle_content": $PROJECT_GRADLE_ESCAPED,
    "app_gradle_content": $APP_GRADLE_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "files_modified": $FILES_MODIFIED,
    "checksums_changed": $CHECKSUMS_CHANGED,
    "kapt_tasks_ran": $KAPT_TASKS_RAN,
    "ksp_tasks_ran": $KSP_TASKS_RAN,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "task_end_timestamp": $(date +%s)
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="