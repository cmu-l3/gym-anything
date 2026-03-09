#!/bin/bash
echo "=== Exporting import_gradle_project result ==="

source /workspace/scripts/task_utils.sh

PROJECT_ROOT="/home/ga/projects/datautils"
WORKSPACE_PROJECT="/home/ga/eclipse-workspace/datautils" 
# Note: When importing Gradle project in place, metadata stays in PROJECT_ROOT. 
# If imported into workspace, it might be in WORKSPACE_PROJECT. 
# We check PROJECT_ROOT for metadata mostly as "Import Existing Gradle Project" usually keeps files in place unless specified otherwise.

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check if project was imported (look for .project and .classpath)
IMPORTED="false"
if [ -f "$PROJECT_ROOT/.project" ] && [ -f "$PROJECT_ROOT/.classpath" ]; then
    IMPORTED="true"
elif [ -f "$WORKSPACE_PROJECT/.project" ]; then
    IMPORTED="true"
    # If moved to workspace, update root for subsequent checks
    PROJECT_ROOT="$WORKSPACE_PROJECT"
fi

# 2. Check build.gradle for dependency
BUILD_GRADLE_CONTENT=""
DEPENDENCY_ADDED="false"
if [ -f "$PROJECT_ROOT/build.gradle" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_ROOT/build.gradle")
    if echo "$BUILD_GRADLE_CONTENT" | grep -q "com.google.guava:guava"; then
        DEPENDENCY_ADDED="true"
    fi
fi

# 3. Check for CollectionHelper.java
CLASS_FILE="$PROJECT_ROOT/src/main/java/com/datautils/util/CollectionHelper.java"
CLASS_FILE_EXISTS="false"
CLASS_FILE_CONTENT=""
CLASS_CREATED_DURING_TASK="false"

if [ -f "$CLASS_FILE" ]; then
    CLASS_FILE_EXISTS="true"
    CLASS_FILE_CONTENT=$(cat "$CLASS_FILE")
    
    FILE_MTIME=$(stat -c %Y "$CLASS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        CLASS_CREATED_DURING_TASK="true"
    fi
fi

# 4. Check if project builds (run gradle explicitly to verify)
# We run this as the 'ga' user to respect permissions and environment
BUILD_SUCCESS="false"
cd "$PROJECT_ROOT"
if sudo -u ga gradle build -x test > /tmp/gradle_build_verify.log 2>&1; then
    BUILD_SUCCESS="true"
fi
BUILD_LOG=$(cat /tmp/gradle_build_verify.log 2>/dev/null | head -n 50)

# 5. Check if the specific class was compiled
COMPILED_CLASS_EXISTS="false"
# Gradle standard output path
if [ -f "$PROJECT_ROOT/build/classes/java/main/com/datautils/util/CollectionHelper.class" ]; then
    COMPILED_CLASS_EXISTS="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare JSON
# Escape contents
BG_ESCAPED=$(echo "$BUILD_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CF_ESCAPED=$(echo "$CLASS_FILE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BL_ESCAPED=$(echo "$BUILD_LOG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_imported": $IMPORTED,
    "dependency_added": $DEPENDENCY_ADDED,
    "class_file_exists": $CLASS_FILE_EXISTS,
    "class_created_during_task": $CLASS_CREATED_DURING_TASK,
    "build_success": $BUILD_SUCCESS,
    "compiled_class_exists": $COMPILED_CLASS_EXISTS,
    "build_gradle_content": $BG_ESCAPED,
    "class_file_content": $CF_ESCAPED,
    "build_log": $BL_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="