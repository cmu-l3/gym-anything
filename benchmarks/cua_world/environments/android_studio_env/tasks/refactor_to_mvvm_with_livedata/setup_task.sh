#!/bin/bash
echo "=== Setting up refactor_to_mvvm_with_livedata task ==="

source /workspace/scripts/task_utils.sh

rm -f /tmp/task_result.json /tmp/task_start.png /tmp/task_end.png 2>/dev/null || true
rm -f /tmp/gradle_output.log /tmp/original_hashes.txt 2>/dev/null || true

PROJECT_DIR="/home/ga/AndroidStudioProjects/TaskManagerApp"
DATA_SOURCE="/workspace/data/TaskManagerApp"
CALC_SOURCE="/workspace/data/CalculatorApp"

# Fresh copy of data project
rm -rf "$PROJECT_DIR" 2>/dev/null || true
mkdir -p /home/ga/AndroidStudioProjects
cp -r "$DATA_SOURCE" "$PROJECT_DIR"

# Copy Gradle wrapper binaries from CalculatorApp (binary files not in source)
cp "$CALC_SOURCE/gradlew" "$PROJECT_DIR/gradlew" 2>/dev/null || true
cp "$CALC_SOURCE/gradlew.bat" "$PROJECT_DIR/gradlew.bat" 2>/dev/null || true
mkdir -p "$PROJECT_DIR/gradle/wrapper"
cp "$CALC_SOURCE/gradle/wrapper/gradle-wrapper.jar" "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true

chown -R ga:ga "$PROJECT_DIR"
find "$PROJECT_DIR" -type d -exec chmod 755 {} \;
find "$PROJECT_DIR" -type f -exec chmod 644 {} \;
chmod +x "$PROJECT_DIR/gradlew"

PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/taskmanager"

# Record original file hashes for change detection
{
    echo "ORIG_BUILD_HASH=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_LIST_HASH=$(md5sum "$PKG_DIR/ui/TaskListActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_ADD_HASH=$(md5sum "$PKG_DIR/ui/AddTaskActivity.kt" 2>/dev/null | awk '{print $1}')"
    echo "ORIG_DETAIL_HASH=$(md5sum "$PKG_DIR/ui/TaskDetailActivity.kt" 2>/dev/null | awk '{print $1}')"
} > /tmp/original_hashes.txt

date +%s > /tmp/task_start_timestamp

setup_android_studio_project "$PROJECT_DIR" "TaskManagerApp" 150
take_screenshot /tmp/task_start.png

echo "=== Setup Complete ==="
