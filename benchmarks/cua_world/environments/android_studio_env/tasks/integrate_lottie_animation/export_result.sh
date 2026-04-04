#!/bin/bash
echo "=== Exporting integrate_lottie_animation result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/BasicApp"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ------------------------------------------------------------------
# 1. Capture Final State
# ------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# 2. Extract Project File Content
# ------------------------------------------------------------------

# Get build.gradle.kts content
BUILD_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
elif [ -f "$PROJECT_DIR/app/build.gradle" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle")
fi

# Get layout XML content
LAYOUT_CONTENT=""
LAYOUT_FILE=$(find "$PROJECT_DIR/app/src/main/res/layout" -name "activity_main.xml" 2>/dev/null | head -1)
if [ -n "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

# Check if asset exists in raw folder
RAW_ASSET_EXISTS="false"
RAW_ASSET_PATH="$PROJECT_DIR/app/src/main/res/raw/android_wave.json"
if [ -f "$RAW_ASSET_PATH" ]; then
    RAW_ASSET_EXISTS="true"
fi

# ------------------------------------------------------------------
# 3. Verify Build Status
# ------------------------------------------------------------------
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running build check..."
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # We use 'assembleDebug' to verify the app compiles with the new library and XML
    # Using 'su - ga' to ensure environment variables are loaded
    BUILD_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug --no-daemon" 2>&1)
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Save partial log for debug
    echo "$BUILD_OUTPUT" | tail -n 50 > /tmp/build_log.txt
fi

# ------------------------------------------------------------------
# 4. JSON Export
# ------------------------------------------------------------------
# Helper to escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

BUILD_GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
LAYOUT_JSON=$(escape_json "$LAYOUT_CONTENT")

cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "build_gradle_content": $BUILD_GRADLE_JSON,
    "layout_xml_content": $LAYOUT_JSON,
    "raw_asset_exists": $RAW_ASSET_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "Export complete."