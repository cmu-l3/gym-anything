#!/bin/bash
echo "=== Exporting refactor_rename_class result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/CalculatorApp"
SRC_DIR="$PROJECT_DIR/app/src/main/java/com/example/calculator"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result flags
OLD_FILE_EXISTS="false"
NEW_FILE_EXISTS="false"
BUILD_SUCCESS="false"

# Initialize content variables
CALCULATOR_CONTENT=""
CALC_ACTIVITY_CONTENT=""

# --- Check if old file CalcEngine.kt still exists ---
if [ -f "$SRC_DIR/CalcEngine.kt" ]; then
    OLD_FILE_EXISTS="true"
fi

# --- Check if new file Calculator.kt exists ---
if [ -f "$SRC_DIR/Calculator.kt" ]; then
    NEW_FILE_EXISTS="true"
    CALCULATOR_CONTENT=$(cat "$SRC_DIR/Calculator.kt" 2>/dev/null)
fi

# --- Read CalcActivity.kt content ---
if [ -f "$SRC_DIR/CalcActivity.kt" ]; then
    CALC_ACTIVITY_CONTENT=$(cat "$SRC_DIR/CalcActivity.kt" 2>/dev/null)
fi

# --- Try to build the project ---
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR" && \
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    else
        # Try a lighter check if full build fails
        cd "$PROJECT_DIR" && \
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_compile_output.log 2>&1
        if [ $? -eq 0 ]; then
            BUILD_SUCCESS="true"
        fi
    fi
fi

# --- Escape content for JSON ---
CALCULATOR_ESCAPED=$(printf '%s' "$CALCULATOR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CALC_ACTIVITY_ESCAPED=$(printf '%s' "$CALC_ACTIVITY_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

GRADLE_OUTPUT=""
if [ -f /tmp/gradle_output.log ]; then
    GRADLE_OUTPUT=$(tail -30 /tmp/gradle_output.log 2>/dev/null)
fi
GRADLE_OUTPUT_ESCAPED=$(printf '%s' "$GRADLE_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# --- List all .kt files in the source directory ---
KT_FILES=$(find "$SRC_DIR" -name "*.kt" -type f 2>/dev/null | sort)
KT_FILES_ESCAPED=$(printf '%s' "$KT_FILES" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# --- Write result JSON ---
RESULT_JSON=$(cat << EOF
{
    "old_file_exists": $OLD_FILE_EXISTS,
    "new_file_exists": $NEW_FILE_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "calculator_content": $CALCULATOR_ESCAPED,
    "calc_activity_content": $CALC_ACTIVITY_ESCAPED,
    "gradle_output": $GRADLE_OUTPUT_ESCAPED,
    "kt_files": $KT_FILES_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
