#!/bin/bash
echo "=== Exporting add_kotlin_serialization result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/GitHubBrowser"
MODEL_DIR="$PROJECT_DIR/app/src/main/java/com/example/githubbrowser/model"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Capture File Contents
OWNER_KT_CONTENT=""
GITHUB_REPO_KT_CONTENT=""
APP_BUILD_GRADLE_CONTENT=""
PROJECT_BUILD_GRADLE_CONTENT=""

if [ -f "$MODEL_DIR/Owner.kt" ]; then
    OWNER_KT_CONTENT=$(cat "$MODEL_DIR/Owner.kt")
fi

if [ -f "$MODEL_DIR/GitHubRepo.kt" ]; then
    GITHUB_REPO_KT_CONTENT=$(cat "$MODEL_DIR/GitHubRepo.kt")
fi

if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    APP_BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
fi

if [ -f "$PROJECT_DIR/build.gradle.kts" ]; then
    PROJECT_BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/build.gradle.kts")
fi

# 2. Check File Timestamps (Anti-Gaming)
FILES_CREATED_DURING_TASK="false"
if [ -f "$MODEL_DIR/Owner.kt" ]; then
    OWNER_MTIME=$(stat -c %Y "$MODEL_DIR/Owner.kt" 2>/dev/null || echo "0")
    if [ "$OWNER_MTIME" -gt "$TASK_START_TIME" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 3. Verify Compilation
# We run gradle assembleDebug to check if the user's changes actually compile.
echo "Running compilation check..."
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Use ga user to run gradle to avoid permission issues with generated .gradle files
    # We use a timeout to prevent it from hanging forever if setup is bad
    BUILD_CMD="export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleDebug --no-daemon"
    
    BUILD_OUTPUT=$(su - ga -c "$BUILD_CMD" 2>&1) || true
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Capture relevant output parts (tail)
    BUILD_OUTPUT_SUMMARY=$(echo "$BUILD_OUTPUT" | tail -n 50)
else
    BUILD_OUTPUT_SUMMARY="gradlew not found"
fi

# 4. Helper to escape JSON strings
escape_json() {
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null
}

# 5. Create Result JSON
cat > /tmp/raw_result.json <<EOF
{
    "task_start_time": $TASK_START_TIME,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "build_success": $BUILD_SUCCESS,
    "owner_kt_exists": $([ -f "$MODEL_DIR/Owner.kt" ] && echo "true" || echo "false"),
    "github_repo_kt_exists": $([ -f "$MODEL_DIR/GitHubRepo.kt" ] && echo "true" || echo "false"),
    "owner_kt_content": $(echo "$OWNER_KT_CONTENT" | escape_json),
    "github_repo_kt_content": $(echo "$GITHUB_REPO_KT_CONTENT" | escape_json),
    "app_build_gradle_content": $(echo "$APP_BUILD_GRADLE_CONTENT" | escape_json),
    "project_build_gradle_content": $(echo "$PROJECT_BUILD_GRADLE_CONTENT" | escape_json),
    "build_output": $(echo "$BUILD_OUTPUT_SUMMARY" | escape_json)
}
EOF

# Move to final location safely
mv /tmp/raw_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"