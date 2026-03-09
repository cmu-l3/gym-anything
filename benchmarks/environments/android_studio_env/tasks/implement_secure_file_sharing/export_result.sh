#!/bin/bash
echo "=== Exporting implement_secure_file_sharing result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/LogShareApp"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
XML_PATH="$PROJECT_DIR/app/src/main/res/xml/provider_paths.xml"
MAIN_ACTIVITY_PATH="$PROJECT_DIR/app/src/main/java/com/example/logshare/MainActivity.kt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# ------------------------------------------------------------------
# 1. Read File Contents
# ------------------------------------------------------------------

MANIFEST_CONTENT=""
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

XML_CONTENT=""
XML_EXISTS="false"
if [ -f "$XML_PATH" ]; then
    XML_EXISTS="true"
    XML_CONTENT=$(cat "$XML_PATH")
fi

MAIN_ACTIVITY_CONTENT=""
if [ -f "$MAIN_ACTIVITY_PATH" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY_PATH")
fi

# ------------------------------------------------------------------
# 2. Attempt Compilation
# ------------------------------------------------------------------
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting Gradle build..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true

    # Clean first to ensure we test current state
    # Set env vars for headless gradle run
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew clean assembleDebug --no-daemon > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    if [ -f /tmp/gradle_output.log ]; then
        BUILD_OUTPUT=$(tail -n 20 /tmp/gradle_output.log)
    fi
fi

# ------------------------------------------------------------------
# 3. Create Result JSON
# ------------------------------------------------------------------

# Helper for JSON escaping
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

MANIFEST_ESCAPED=$(escape_json "$MANIFEST_CONTENT")
XML_ESCAPED=$(escape_json "$XML_CONTENT")
MAIN_ACTIVITY_ESCAPED=$(escape_json "$MAIN_ACTIVITY_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

RESULT_JSON=$(cat << EOF
{
    "manifest_exists": $([ -f "$MANIFEST_PATH" ] && echo "true" || echo "false"),
    "manifest_content": $MANIFEST_ESCAPED,
    "xml_exists": $XML_EXISTS,
    "xml_content": $XML_ESCAPED,
    "main_activity_exists": $([ -f "$MAIN_ACTIVITY_PATH" ] && echo "true" || echo "false"),
    "main_activity_content": $MAIN_ACTIVITY_ESCAPED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="