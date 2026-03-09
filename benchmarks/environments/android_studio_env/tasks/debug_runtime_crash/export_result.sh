#!/bin/bash
echo "=== Exporting debug_runtime_crash result ==="

source /workspace/scripts/task_utils.sh

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/NotepadApp"
PKG_PATH="com/example/notepad"
SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"

# Take final screenshot
take_screenshot /tmp/task_end.png

# ---- Read current content of all 4 bug files ----

ACTIVITY_CONTENT=""
if [ -f "$SRC_DIR/NotepadActivity.kt" ]; then
    ACTIVITY_CONTENT=$(cat "$SRC_DIR/NotepadActivity.kt" 2>/dev/null)
fi

FORMATTER_CONTENT=""
if [ -f "$SRC_DIR/NoteFormatter.kt" ]; then
    FORMATTER_CONTENT=$(cat "$SRC_DIR/NoteFormatter.kt" 2>/dev/null)
fi

VALIDATOR_CONTENT=""
if [ -f "$SRC_DIR/NoteValidator.kt" ]; then
    VALIDATOR_CONTENT=$(cat "$SRC_DIR/NoteValidator.kt" 2>/dev/null)
fi

NOTE_CONTENT=""
if [ -f "$SRC_DIR/Note.kt" ]; then
    NOTE_CONTENT=$(cat "$SRC_DIR/Note.kt" 2>/dev/null)
fi

# ---- Compare with original hashes to detect changes ----

ACTIVITY_CHANGED="false"
FORMATTER_CHANGED="false"
VALIDATOR_CHANGED="false"
NOTE_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt

    CURR=$(md5sum "$SRC_DIR/NotepadActivity.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_ACTIVITY_HASH" ] && [ -n "$CURR" ] && ACTIVITY_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/NoteFormatter.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_FORMATTER_HASH" ] && [ -n "$CURR" ] && FORMATTER_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/NoteValidator.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_VALIDATOR_HASH" ] && [ -n "$CURR" ] && VALIDATOR_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/Note.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_NOTE_HASH" ] && [ -n "$CURR" ] && NOTE_CHANGED="true"
fi

# ---- Try to run Gradle build to check if build succeeds ----

BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true

    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1

    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "assembleDebug succeeded!"
    else
        echo "assembleDebug failed, trying compileDebugKotlin..."
        cd "$PROJECT_DIR"
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_output.log 2>&1

        if [ $? -eq 0 ]; then
            BUILD_SUCCESS="true"
            echo "compileDebugKotlin succeeded!"
        else
            echo "Build failed."
        fi
    fi

    if [ -f /tmp/gradle_output.log ]; then
        BUILD_OUTPUT=$(tail -30 /tmp/gradle_output.log 2>/dev/null)
    fi
fi

# ---- Escape content for JSON ----

ACT_ESC=$(printf '%s' "$ACTIVITY_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FMT_ESC=$(printf '%s' "$FORMATTER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
VAL_ESC=$(printf '%s' "$VALIDATOR_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
NOTE_ESC=$(printf '%s' "$NOTE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# ---- Write result JSON ----

RESULT_JSON=$(cat << EOF
{
    "activity_content": $ACT_ESC,
    "activity_changed": $ACTIVITY_CHANGED,
    "formatter_content": $FMT_ESC,
    "formatter_changed": $FORMATTER_CHANGED,
    "validator_content": $VAL_ESC,
    "validator_changed": $VALIDATOR_CHANGED,
    "note_content": $NOTE_ESC,
    "note_changed": $NOTE_CHANGED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="
