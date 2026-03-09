#!/bin/bash
echo "=== Exporting implement_hilt_dependency_injection result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/ExpenseTrackerApp"
PKG_DIR="$PROJECT_DIR/app/src/main/java/com/example/expensetracker"

take_screenshot /tmp/task_end.png

# Read key source files
BUILD_GRADLE=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
APP_KT=$(cat "$PKG_DIR/ExpenseApp.kt" 2>/dev/null)
MAIN_KT=$(cat "$PKG_DIR/ui/MainActivity.kt" 2>/dev/null)
ADD_KT=$(cat "$PKG_DIR/ui/AddExpenseActivity.kt" 2>/dev/null)
SETTINGS_KT=$(cat "$PKG_DIR/ui/SettingsActivity.kt" 2>/dev/null)

# Look for DI module file (may be in di/ or any subpackage)
MODULE_KT=$(find "$PKG_DIR" -name "*.kt" -exec grep -l "@Module" {} \; 2>/dev/null | head -1)
MODULE_CONTENT=$(cat "$MODULE_KT" 2>/dev/null)

# Change detection
BUILD_CHANGED="false"
APP_CHANGED="false"
MAIN_CHANGED="false"
ADD_CHANGED="false"
SETTINGS_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR" ] && BUILD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ExpenseApp.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_APP_HASH" ] && [ -n "$CURR" ] && APP_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/MainActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_MAIN_HASH" ] && [ -n "$CURR" ] && MAIN_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/AddExpenseActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ADD_HASH" ] && [ -n "$CURR" ] && ADD_CHANGED="true"
    CURR=$(md5sum "$PKG_DIR/ui/SettingsActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SETTINGS_HASH" ] && [ -n "$CURR" ] && SETTINGS_CHANGED="true"
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
BUILD_GRADLE_ESC=$(printf '%s' "$BUILD_GRADLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
APP_ESC=$(printf '%s' "$APP_KT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MAIN_ESC=$(printf '%s' "$MAIN_KT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
ADD_ESC=$(printf '%s' "$ADD_KT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SETTINGS_ESC=$(printf '%s' "$SETTINGS_KT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MODULE_ESC=$(printf '%s' "$MODULE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MODULE_PATH_ESC=$(printf '%s' "${MODULE_KT:-}" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "build_gradle_content": $BUILD_GRADLE_ESC,
    "build_gradle_changed": $BUILD_CHANGED,
    "app_kt_content": $APP_ESC,
    "app_kt_changed": $APP_CHANGED,
    "main_activity_content": $MAIN_ESC,
    "main_activity_changed": $MAIN_CHANGED,
    "add_expense_content": $ADD_ESC,
    "add_expense_changed": $ADD_CHANGED,
    "settings_activity_content": $SETTINGS_ESC,
    "settings_activity_changed": $SETTINGS_CHANGED,
    "module_content": $MODULE_ESC,
    "module_path": $MODULE_PATH_ESC,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
