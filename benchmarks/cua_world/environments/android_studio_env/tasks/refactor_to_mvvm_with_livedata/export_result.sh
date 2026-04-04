#!/bin/bash
echo "=== Exporting refactor_to_mvvm_with_livedata result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskManagerApp"
PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/taskmanager"

take_screenshot /tmp/task_end.png

# Read key source files
BUILD_GRADLE=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
LIST_ACT=$(cat "$PKG_DIR/ui/TaskListActivity.kt" 2>/dev/null)
ADD_ACT=$(cat "$PKG_DIR/ui/AddTaskActivity.kt" 2>/dev/null)
DETAIL_ACT=$(cat "$PKG_DIR/ui/TaskDetailActivity.kt" 2>/dev/null)

# Look for ViewModel files (may be in viewmodel/ subfolder)
VM_FILES=$(find "$PKG_DIR" -name "*ViewModel*.kt" -o -name "*ViewModel.kt" 2>/dev/null | sort)
VM_COUNT=$(echo "$VM_FILES" | grep -c ".kt" 2>/dev/null || echo 0)
VM_CONTENTS=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    content=$(cat "$f" 2>/dev/null)
    name=$(basename "$f")
    VM_CONTENTS="$VM_CONTENTS\n\n// FILE: $name\n$content"
done <<< "$VM_FILES"

# Change detection
BUILD_CHANGED="false"
LIST_CHANGED="false"
ADD_CHANGED="false"
DETAIL_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR" ] && BUILD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/TaskListActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_LIST_HASH" ] && [ -n "$CURR" ] && LIST_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/AddTaskActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ADD_HASH" ] && [ -n "$CURR" ] && ADD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/TaskDetailActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_DETAIL_HASH" ] && [ -n "$CURR" ] && DETAIL_CHANGED="true"
fi

# Build
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    [ $? -eq 0 ] && BUILD_SUCCESS="true"
    if [ "$BUILD_SUCCESS" = "false" ]; then
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon >> /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
fi
BUILD_OUTPUT=$(tail -40 /tmp/gradle_output.log 2>/dev/null)

# Escape for JSON
BUILD_ESC=$(printf '%s' "$BUILD_GRADLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
LIST_ESC=$(printf '%s' "$LIST_ACT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ADD_ESC=$(printf '%s' "$ADD_ACT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
DETAIL_ESC=$(printf '%s' "$DETAIL_ACT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
VM_ESC=$(printf '%s' "$VM_CONTENTS" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_gradle_content": $BUILD_ESC,
    "build_gradle_changed": $BUILD_CHANGED,
    "list_activity_content": $LIST_ESC,
    "list_activity_changed": $LIST_CHANGED,
    "add_activity_content": $ADD_ESC,
    "add_activity_changed": $ADD_CHANGED,
    "detail_activity_content": $DETAIL_ESC,
    "detail_activity_changed": $DETAIL_CHANGED,
    "viewmodel_contents": $VM_ESC,
    "viewmodel_count": $VM_COUNT,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
