#!/bin/bash
echo "=== Exporting implement_responsive_dimens result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SocialApp"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_profile.xml"
BASE_DIMENS="$PROJECT_DIR/app/src/main/res/values/dimens.xml"
TABLET_DIR="$PROJECT_DIR/app/src/main/res/values-sw600dp"
TABLET_DIMENS="$TABLET_DIR/dimens.xml"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize flags
LAYOUT_EXISTS="false"
BASE_DIMENS_EXISTS="false"
TABLET_DIR_EXISTS="false"
TABLET_DIMENS_EXISTS="false"
BUILD_SUCCESS="false"

# Read file contents
LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE" 2>/dev/null)
fi

BASE_DIMENS_CONTENT=""
if [ -f "$BASE_DIMENS" ]; then
    BASE_DIMENS_EXISTS="true"
    BASE_DIMENS_CONTENT=$(cat "$BASE_DIMENS" 2>/dev/null)
fi

TABLET_DIMENS_CONTENT=""
if [ -d "$TABLET_DIR" ]; then
    TABLET_DIR_EXISTS="true"
    if [ -f "$TABLET_DIMENS" ]; then
        TABLET_DIMENS_EXISTS="true"
        TABLET_DIMENS_CONTENT=$(cat "$TABLET_DIMENS" 2>/dev/null)
    fi
fi

# Try to build
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    
    # Use standard env vars for Android
    export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
    export ANDROID_SDK_ROOT=/opt/android-sdk
    
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

LAYOUT_JSON=$(escape_json "$LAYOUT_CONTENT")
BASE_DIMENS_JSON=$(escape_json "$BASE_DIMENS_CONTENT")
TABLET_DIMENS_JSON=$(escape_json "$TABLET_DIMENS_CONTENT")

# Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "layout_exists": $LAYOUT_EXISTS,
    "base_dimens_exists": $BASE_DIMENS_EXISTS,
    "tablet_dir_exists": $TABLET_DIR_EXISTS,
    "tablet_dimens_exists": $TABLET_DIMENS_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "layout_content": $LAYOUT_JSON,
    "base_dimens_content": $BASE_DIMENS_JSON,
    "tablet_dimens_content": $TABLET_DIMENS_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="