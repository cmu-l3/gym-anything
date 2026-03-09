#!/bin/bash
echo "=== Exporting convert_java_to_kotlin result ==="

source /workspace/scripts/task_utils.sh

# Record task end timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Project Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/RoomWordSample"
PACKAGE_DIR="$PROJECT_DIR/app/src/main/java/com/example/roomwordsample"

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- Check Files ---

# Files to be converted
WORD_KT="$PACKAGE_DIR/Word.kt"
WORD_DAO_KT="$PACKAGE_DIR/WordDao.kt"
WORD_VM_KT="$PACKAGE_DIR/WordViewModel.kt"

# Original files (should be gone)
WORD_JAVA="$PACKAGE_DIR/Word.java"
WORD_DAO_JAVA="$PACKAGE_DIR/WordDao.java"
WORD_VM_JAVA="$PACKAGE_DIR/WordViewModel.java"

# Untouched files (should remain)
REPO_JAVA="$PACKAGE_DIR/WordRepository.java"
DB_JAVA="$PACKAGE_DIR/WordRoomDatabase.java"

# Capture existence
WORD_KT_EXISTS=$([ -f "$WORD_KT" ] && echo "true" || echo "false")
WORD_DAO_KT_EXISTS=$([ -f "$WORD_DAO_KT" ] && echo "true" || echo "false")
WORD_VM_KT_EXISTS=$([ -f "$WORD_VM_KT" ] && echo "true" || echo "false")

WORD_JAVA_EXISTS=$([ -f "$WORD_JAVA" ] && echo "true" || echo "false")
WORD_DAO_JAVA_EXISTS=$([ -f "$WORD_DAO_JAVA" ] && echo "true" || echo "false")
WORD_VM_JAVA_EXISTS=$([ -f "$WORD_VM_JAVA" ] && echo "true" || echo "false")

REPO_JAVA_EXISTS=$([ -f "$REPO_JAVA" ] && echo "true" || echo "false")

# Capture content for validation (max 100 lines)
WORD_KT_CONTENT=""
[ -f "$WORD_KT" ] && WORD_KT_CONTENT=$(cat "$WORD_KT" | head -100)

WORD_DAO_KT_CONTENT=""
[ -f "$WORD_DAO_KT" ] && WORD_DAO_KT_CONTENT=$(cat "$WORD_DAO_KT" | head -100)

WORD_VM_KT_CONTENT=""
[ -f "$WORD_VM_KT" ] && WORD_VM_KT_CONTENT=$(cat "$WORD_VM_KT" | head -100)

# Capture Timestamps (Anti-Gaming)
WORD_KT_MTIME=$(stat -c %Y "$WORD_KT" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$WORD_KT_MTIME" -ge "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# --- Verify Build ---
# We try to build. If it builds, it means conversion + interoperability is correct.
BUILD_SUCCESS="false"
BUILD_OUTPUT=""
APK_PATH="$PROJECT_DIR/app/build/outputs/apk/debug/app-debug.apk"

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle build..."
    cd "$PROJECT_DIR"
    
    # We use a timeout to prevent hanging forever
    timeout 300 su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleDebug --no-daemon" > /tmp/gradle_output.log 2>&1
    GRADLE_EXIT=$?
    
    if [ $GRADLE_EXIT -eq 0 ] && [ -f "$APK_PATH" ]; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 20 /tmp/gradle_output.log)
fi

# Escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

WORD_KT_ESCAPED=$(escape_json "$WORD_KT_CONTENT")
WORD_DAO_KT_ESCAPED=$(escape_json "$WORD_DAO_KT_CONTENT")
WORD_VM_KT_ESCAPED=$(escape_json "$WORD_VM_KT_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# Create JSON
cat > /tmp/task_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "word_kt_exists": $WORD_KT_EXISTS,
    "word_dao_kt_exists": $WORD_DAO_KT_EXISTS,
    "word_vm_kt_exists": $WORD_VM_KT_EXISTS,
    "word_java_exists": $WORD_JAVA_EXISTS,
    "word_dao_java_exists": $WORD_DAO_JAVA_EXISTS,
    "word_vm_java_exists": $WORD_VM_JAVA_EXISTS,
    "repo_java_exists": $REPO_JAVA_EXISTS,
    "word_kt_content": $WORD_KT_ESCAPED,
    "word_dao_kt_content": $WORD_DAO_KT_ESCAPED,
    "word_vm_kt_content": $WORD_VM_KT_ESCAPED,
    "created_during_task": $CREATED_DURING_TASK,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="