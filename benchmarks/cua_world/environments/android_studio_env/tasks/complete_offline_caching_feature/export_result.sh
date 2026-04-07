#!/bin/bash
echo "=== Exporting complete_offline_caching_feature result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end.png

PROJECT_DIR="/home/ga/AndroidStudioProjects/StudyPlannerApp"
SRC_DIR="$PROJECT_DIR/app/src/main/java/com/example/studyplanner"

# Read file contents
APP_BUILD_GRADLE=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    APP_BUILD_GRADLE=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
fi

CONVERTERS_CONTENT=""
if [ -f "$SRC_DIR/data/local/Converters.kt" ]; then
    CONVERTERS_CONTENT=$(cat "$SRC_DIR/data/local/Converters.kt" 2>/dev/null)
fi

MIGRATIONS_CONTENT=""
if [ -f "$SRC_DIR/data/local/Migrations.kt" ]; then
    MIGRATIONS_CONTENT=$(cat "$SRC_DIR/data/local/Migrations.kt" 2>/dev/null)
fi

FLASHCARD_DTO_CONTENT=""
if [ -f "$SRC_DIR/data/remote/FlashCardDto.kt" ]; then
    FLASHCARD_DTO_CONTENT=$(cat "$SRC_DIR/data/remote/FlashCardDto.kt" 2>/dev/null)
fi

OFFLINE_REPO_CONTENT=""
if [ -f "$SRC_DIR/data/repository/OfflineCacheRepository.kt" ]; then
    OFFLINE_REPO_CONTENT=$(cat "$SRC_DIR/data/repository/OfflineCacheRepository.kt" 2>/dev/null)
fi

SUBJECT_VM_CONTENT=""
if [ -f "$SRC_DIR/ui/subjects/SubjectListViewModel.kt" ]; then
    SUBJECT_VM_CONTENT=$(cat "$SRC_DIR/ui/subjects/SubjectListViewModel.kt" 2>/dev/null)
fi

SESSION_VM_CONTENT=""
if [ -f "$SRC_DIR/ui/sessions/SessionLogViewModel.kt" ]; then
    SESSION_VM_CONTENT=$(cat "$SRC_DIR/ui/sessions/SessionLogViewModel.kt" 2>/dev/null)
fi

# Check for file changes
APP_BUILD_CHANGED="false"
CONVERTERS_CHANGED="false"
MIGRATIONS_CHANGED="false"
FLASHCARD_DTO_CHANGED="false"
OFFLINE_REPO_CHANGED="false"
SUBJECT_VM_CHANGED="false"
SESSION_VM_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt

    CURR=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_APP_BUILD_HASH" ] && [ -n "$CURR" ] && APP_BUILD_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/data/local/Converters.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_CONVERTERS_HASH" ] && [ -n "$CURR" ] && CONVERTERS_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/data/local/Migrations.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_MIGRATIONS_HASH" ] && [ -n "$CURR" ] && MIGRATIONS_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/data/remote/FlashCardDto.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_FLASHCARD_DTO_HASH" ] && [ -n "$CURR" ] && FLASHCARD_DTO_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/data/repository/OfflineCacheRepository.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_OFFLINE_REPO_HASH" ] && [ -n "$CURR" ] && OFFLINE_REPO_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/ui/subjects/SubjectListViewModel.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SUBJECT_VM_HASH" ] && [ -n "$CURR" ] && SUBJECT_VM_CHANGED="true"

    CURR=$(md5sum "$SRC_DIR/ui/sessions/SessionLogViewModel.kt" 2>/dev/null | awk '{print $1}')
    [ "$CURR" != "$ORIG_SESSION_VM_HASH" ] && [ -n "$CURR" ] && SESSION_VM_CHANGED="true"
fi

# Run gradle build
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    else
        # Fallback to compile-only
        ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
fi
BUILD_OUTPUT=$(tail -50 /tmp/gradle_output.log 2>/dev/null)

# JSON-escape all content
APP_BUILD_ESC=$(printf '%s' "$APP_BUILD_GRADLE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
CONVERTERS_ESC=$(printf '%s' "$CONVERTERS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
MIGRATIONS_ESC=$(printf '%s' "$MIGRATIONS_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
FLASHCARD_DTO_ESC=$(printf '%s' "$FLASHCARD_DTO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OFFLINE_REPO_ESC=$(printf '%s' "$OFFLINE_REPO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SUBJECT_VM_ESC=$(printf '%s' "$SUBJECT_VM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
SESSION_VM_ESC=$(printf '%s' "$SESSION_VM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUTPUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "app_build_gradle_content": $APP_BUILD_ESC,
    "app_build_gradle_changed": $APP_BUILD_CHANGED,
    "converters_content": $CONVERTERS_ESC,
    "converters_changed": $CONVERTERS_CHANGED,
    "migrations_content": $MIGRATIONS_ESC,
    "migrations_changed": $MIGRATIONS_CHANGED,
    "flashcard_dto_content": $FLASHCARD_DTO_ESC,
    "flashcard_dto_changed": $FLASHCARD_DTO_CHANGED,
    "offline_repo_content": $OFFLINE_REPO_ESC,
    "offline_repo_changed": $OFFLINE_REPO_CHANGED,
    "subject_vm_content": $SUBJECT_VM_ESC,
    "subject_vm_changed": $SUBJECT_VM_CHANGED,
    "session_vm_content": $SESSION_VM_ESC,
    "session_vm_changed": $SESSION_VM_CHANGED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="
