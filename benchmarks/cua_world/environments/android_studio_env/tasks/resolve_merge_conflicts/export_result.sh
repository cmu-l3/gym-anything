#!/bin/bash
echo "=== Exporting merge conflict resolution result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskMaster"
GRADLE_FILE="$PROJECT_DIR/app/build.gradle.kts"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Check Git Status
echo "Checking Git status..."
GIT_STATUS_CLEAN="false"
GIT_MERGE_COMMIT_EXISTS="false"
cd "$PROJECT_DIR"

if [ -z "$(git status --porcelain)" ]; then
    GIT_STATUS_CLEAN="true"
fi

# Check if last commit is a merge (has 2 parents)
LAST_COMMIT_PARENTS=$(git log -1 --format=%p | wc -w)
if [ "$LAST_COMMIT_PARENTS" -eq 2 ]; then
    GIT_MERGE_COMMIT_EXISTS="true"
fi

# 2. Check File Contents
echo "Checking file contents..."
GRADLE_CONTENT=""
LAYOUT_CONTENT=""

if [ -f "$GRADLE_FILE" ]; then
    GRADLE_CONTENT=$(cat "$GRADLE_FILE")
fi

if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

# 3. Check for Build Success
echo "Checking build..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    # Fix permissions just in case
    chmod +x "$PROJECT_DIR/gradlew"
    
    # Run assembleDebug
    BUILD_OUTPUT=$(su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; export ANDROID_HOME=/opt/android-sdk; ./gradlew assembleDebug --no-daemon 2>&1" 2>&1)
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# 4. Prepare JSON result
echo "Preparing result JSON..."

# Helper to escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

GRADLE_ESCAPED=$(escape_json "$GRADLE_CONTENT")
LAYOUT_ESCAPED=$(escape_json "$LAYOUT_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

cat > /tmp/task_result.json << EOF
{
  "git_status_clean": $GIT_STATUS_CLEAN,
  "git_merge_commit_exists": $GIT_MERGE_COMMIT_EXISTS,
  "build_success": $BUILD_SUCCESS,
  "gradle_content": $GRADLE_ESCAPED,
  "layout_content": $LAYOUT_ESCAPED,
  "build_output": $BUILD_OUTPUT_ESCAPED,
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="