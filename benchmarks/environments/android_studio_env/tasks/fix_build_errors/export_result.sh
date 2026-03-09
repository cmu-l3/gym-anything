#!/bin/bash
echo "=== Exporting fix_build_errors result ==="

source /workspace/scripts/task_utils.sh

# Project paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/BrokenApp"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/MainActivity.kt"
PLANT_KT="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/Plant.kt"
PLANT_REPO="$PROJECT_DIR/app/src/main/java/com/google/samples/apps/sunflower/data/PlantRepository.kt"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"

# Take final screenshot
take_screenshot /tmp/task_end.png

# ---- Read current content of all 4 error files ----

MAIN_ACTIVITY_CONTENT=""
MAIN_ACTIVITY_EXISTS="false"
if [ -f "$MAIN_ACTIVITY" ]; then
    MAIN_ACTIVITY_EXISTS="true"
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY" 2>/dev/null)
fi

PLANT_KT_CONTENT=""
PLANT_KT_EXISTS="false"
if [ -f "$PLANT_KT" ]; then
    PLANT_KT_EXISTS="true"
    PLANT_KT_CONTENT=$(cat "$PLANT_KT" 2>/dev/null)
fi

PLANT_REPO_CONTENT=""
PLANT_REPO_EXISTS="false"
if [ -f "$PLANT_REPO" ]; then
    PLANT_REPO_EXISTS="true"
    PLANT_REPO_CONTENT=$(cat "$PLANT_REPO" 2>/dev/null)
fi

BUILD_GRADLE_CONTENT=""
BUILD_GRADLE_EXISTS="false"
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_EXISTS="true"
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE" 2>/dev/null)
fi

# ---- Compare with original hashes to detect changes ----

MAIN_ACTIVITY_CHANGED="false"
PLANT_KT_CHANGED="false"
PLANT_REPO_CHANGED="false"
BUILD_GRADLE_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt

    CURRENT_MAIN=$(md5sum "$MAIN_ACTIVITY" 2>/dev/null | awk '{print $1}')
    CURRENT_PLANT=$(md5sum "$PLANT_KT" 2>/dev/null | awk '{print $1}')
    CURRENT_REPO=$(md5sum "$PLANT_REPO" 2>/dev/null | awk '{print $1}')
    CURRENT_GRADLE=$(md5sum "$BUILD_GRADLE" 2>/dev/null | awk '{print $1}')

    if [ "$CURRENT_MAIN" != "$ORIG_MAIN_HASH" ] && [ -n "$CURRENT_MAIN" ]; then
        MAIN_ACTIVITY_CHANGED="true"
    fi
    if [ "$CURRENT_PLANT" != "$ORIG_PLANT_HASH" ] && [ -n "$CURRENT_PLANT" ]; then
        PLANT_KT_CHANGED="true"
    fi
    if [ "$CURRENT_REPO" != "$ORIG_REPO_HASH" ] && [ -n "$CURRENT_REPO" ]; then
        PLANT_REPO_CHANGED="true"
    fi
    if [ "$CURRENT_GRADLE" != "$ORIG_GRADLE_HASH" ] && [ -n "$CURRENT_GRADLE" ]; then
        BUILD_GRADLE_CHANGED="true"
    fi
fi

# ---- Try to run Gradle build to check if build succeeds ----

BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle assembleDebug..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true

    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1

    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build succeeded!"
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
        BUILD_OUTPUT=$(tail -50 /tmp/gradle_output.log 2>/dev/null)
    fi
fi

# ---- Escape content for JSON ----

MAIN_ACTIVITY_ESCAPED=$(printf '%s' "$MAIN_ACTIVITY_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
PLANT_KT_ESCAPED=$(printf '%s' "$PLANT_KT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
PLANT_REPO_ESCAPED=$(printf '%s' "$PLANT_REPO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_GRADLE_ESCAPED=$(printf '%s' "$BUILD_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUTPUT_ESCAPED=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# ---- Write result JSON ----

RESULT_JSON=$(cat << EOF
{
    "main_activity_exists": $MAIN_ACTIVITY_EXISTS,
    "main_activity_changed": $MAIN_ACTIVITY_CHANGED,
    "main_activity_content": $MAIN_ACTIVITY_ESCAPED,
    "plant_kt_exists": $PLANT_KT_EXISTS,
    "plant_kt_changed": $PLANT_KT_CHANGED,
    "plant_kt_content": $PLANT_KT_ESCAPED,
    "plant_repo_exists": $PLANT_REPO_EXISTS,
    "plant_repo_changed": $PLANT_REPO_CHANGED,
    "plant_repo_content": $PLANT_REPO_ESCAPED,
    "build_gradle_exists": $BUILD_GRADLE_EXISTS,
    "build_gradle_changed": $BUILD_GRADLE_CHANGED,
    "build_gradle_content": $BUILD_GRADLE_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
