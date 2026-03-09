#!/bin/bash
echo "=== Exporting implement_room_database result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunflowerApp"
PKG_PATH="com/google/samples/apps/sunflower"
SRC_DIR="$PROJECT_DIR/app/src/main/java/$PKG_PATH"

take_screenshot /tmp/task_end.png

# --- Check file existence and read contents ---

PLANT_KT_CONTENT=""
PLANT_KT_EXISTS="false"
if [ -f "$SRC_DIR/data/Plant.kt" ]; then
    PLANT_KT_EXISTS="true"
    PLANT_KT_CONTENT=$(cat "$SRC_DIR/data/Plant.kt" 2>/dev/null)
fi

REPO_CONTENT=""
REPO_EXISTS="false"
if [ -f "$SRC_DIR/data/PlantRepository.kt" ]; then
    REPO_EXISTS="true"
    REPO_CONTENT=$(cat "$SRC_DIR/data/PlantRepository.kt" 2>/dev/null)
fi

BUILD_GRADLE_CONTENT=""
BUILD_GRADLE_EXISTS="false"
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    BUILD_GRADLE_EXISTS="true"
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null)
fi

# Check for new files (DAO and Database)
DAO_CONTENT=""
DAO_EXISTS="false"
# Search for any file containing @Dao in the data directory
DAO_FILE=$(grep -rl "@Dao" "$SRC_DIR/" 2>/dev/null | head -1)
if [ -n "$DAO_FILE" ]; then
    DAO_EXISTS="true"
    DAO_CONTENT=$(cat "$DAO_FILE" 2>/dev/null)
fi

DB_CONTENT=""
DB_EXISTS="false"
# Search for any file containing RoomDatabase in source
DB_FILE=$(grep -rl "RoomDatabase" "$SRC_DIR/" 2>/dev/null | head -1)
if [ -n "$DB_FILE" ]; then
    DB_EXISTS="true"
    DB_CONTENT=$(cat "$DB_FILE" 2>/dev/null)
fi

# --- Check for changes vs baseline ---
PLANT_CHANGED="false"
REPO_CHANGED="false"
BUILD_CHANGED="false"

if [ -f /tmp/original_hashes.txt ]; then
    source /tmp/original_hashes.txt
    CURR_PLANT=$(md5sum "$SRC_DIR/data/Plant.kt" 2>/dev/null | awk '{print $1}')
    CURR_REPO=$(md5sum "$SRC_DIR/data/PlantRepository.kt" 2>/dev/null | awk '{print $1}')
    CURR_BUILD=$(md5sum "$PROJECT_DIR/app/build.gradle.kts" 2>/dev/null | awk '{print $1}')
    [ "$CURR_PLANT" != "$ORIG_PLANT_HASH" ] && [ -n "$CURR_PLANT" ] && PLANT_CHANGED="true"
    [ "$CURR_REPO" != "$ORIG_REPO_HASH" ] && [ -n "$CURR_REPO" ] && REPO_CHANGED="true"
    [ "$CURR_BUILD" != "$ORIG_BUILD_HASH" ] && [ -n "$CURR_BUILD" ] && BUILD_CHANGED="true"
fi

# --- Attempt Gradle build ---
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
    else
        # Try compile only
        JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
        ANDROID_SDK_ROOT=/opt/android-sdk \
        ANDROID_HOME=/opt/android-sdk \
        ./gradlew compileDebugKotlin --no-daemon > /tmp/gradle_output.log 2>&1
        [ $? -eq 0 ] && BUILD_SUCCESS="true"
    fi
    BUILD_OUTPUT=$(tail -50 /tmp/gradle_output.log 2>/dev/null)
fi

# --- Escape and write JSON ---
PLANT_KT_ESC=$(printf '%s' "$PLANT_KT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
REPO_ESC=$(printf '%s' "$REPO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_ESC=$(printf '%s' "$BUILD_GRADLE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
DAO_ESC=$(printf '%s' "$DAO_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
DB_ESC=$(printf '%s' "$DB_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
BUILD_OUT_ESC=$(printf '%s' "$BUILD_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

RESULT_JSON=$(cat << EOF
{
    "plant_kt_exists": $PLANT_KT_EXISTS,
    "plant_kt_changed": $PLANT_CHANGED,
    "plant_kt_content": $PLANT_KT_ESC,
    "repo_exists": $REPO_EXISTS,
    "repo_changed": $REPO_CHANGED,
    "repo_content": $REPO_ESC,
    "build_gradle_exists": $BUILD_GRADLE_EXISTS,
    "build_gradle_changed": $BUILD_CHANGED,
    "build_gradle_content": $BUILD_ESC,
    "dao_exists": $DAO_EXISTS,
    "dao_content": $DAO_ESC,
    "db_exists": $DB_EXISTS,
    "db_content": $DB_ESC,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUT_ESC,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json
echo "=== Export Complete ==="
