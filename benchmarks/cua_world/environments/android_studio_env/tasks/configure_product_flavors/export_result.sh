#!/bin/bash
set -e

echo "=== Exporting Configure Product Flavors result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/AndroidStudioProjects/TodoApp"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
FREE_STRINGS="$PROJECT_DIR/app/src/free/res/values/strings.xml"
PAID_STRINGS="$PROJECT_DIR/app/src/paid/res/values/strings.xml"

# ---- Collect file contents ----
BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

FREE_STRINGS_CONTENT=""
FREE_STRINGS_EXISTS="false"
if [ -f "$FREE_STRINGS" ]; then
    FREE_STRINGS_EXISTS="true"
    FREE_STRINGS_CONTENT=$(cat "$FREE_STRINGS")
fi

PAID_STRINGS_CONTENT=""
PAID_STRINGS_EXISTS="false"
if [ -f "$PAID_STRINGS" ]; then
    PAID_STRINGS_EXISTS="true"
    PAID_STRINGS_CONTENT=$(cat "$PAID_STRINGS")
fi

# ---- Verify timestamps (anti-gaming) ----
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ -f "$BUILD_GRADLE" ]; then
    FILE_MTIME=$(stat -c %Y "$BUILD_GRADLE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# ---- Run Gradle verification ----
echo "Running Gradle tasks to verify configuration..."
GRADLE_VARIANTS_DETECTED="false"
GRADLE_VARIANTS_COUNT=0
GRADLE_VARIANTS_LIST=""
GRADLE_EXIT_CODE=1

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run 'tasks' to list all tasks, filtering for assemble<Flavor>Debug
    GRADLE_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ANDROID_SDK_ROOT=/opt/android-sdk ANDROID_HOME=/opt/android-sdk ./gradlew tasks --all" 2>&1 || true)
    
    # Check exit code of the gradle command itself
    if [ $? -eq 0 ]; then
        GRADLE_EXIT_CODE=0
    fi
    
    # Check output for specific variants
    if echo "$GRADLE_OUTPUT" | grep -qi "assembleFreeDebug"; then
        GRADLE_VARIANTS_COUNT=$((GRADLE_VARIANTS_COUNT + 1))
        GRADLE_VARIANTS_LIST="${GRADLE_VARIANTS_LIST}free "
    fi
    if echo "$GRADLE_OUTPUT" | grep -qi "assemblePaidDebug"; then
        GRADLE_VARIANTS_COUNT=$((GRADLE_VARIANTS_COUNT + 1))
        GRADLE_VARIANTS_LIST="${GRADLE_VARIANTS_LIST}paid "
    fi
    
    if [ $GRADLE_VARIANTS_COUNT -ge 2 ]; then
        GRADLE_VARIANTS_DETECTED="true"
    fi
else
    GRADLE_OUTPUT="Gradle wrapper not found"
fi

# ---- Escape content for JSON ----
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

BG_ESCAPED=$(escape_json "$BUILD_GRADLE_CONTENT")
FS_ESCAPED=$(escape_json "$FREE_STRINGS_CONTENT")
PS_ESCAPED=$(escape_json "$PAID_STRINGS_CONTENT")
GO_ESCAPED=$(escape_json "$GRADLE_OUTPUT")

# ---- Write result JSON ----
cat > /tmp/result_gen.json << EOF
{
    "build_gradle_content": $BG_ESCAPED,
    "free_strings_exists": $FREE_STRINGS_EXISTS,
    "free_strings_content": $FS_ESCAPED,
    "paid_strings_exists": $PAID_STRINGS_EXISTS,
    "paid_strings_content": $PS_ESCAPED,
    "file_modified_during_task": $FILE_MODIFIED,
    "gradle_variants_detected": $GRADLE_VARIANTS_DETECTED,
    "gradle_variants_count": $GRADLE_VARIANTS_COUNT,
    "gradle_output": $GO_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
mv /tmp/result_gen.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="