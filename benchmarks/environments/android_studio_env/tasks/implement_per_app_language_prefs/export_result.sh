#!/bin/bash
echo "=== Exporting implement_per_app_language_prefs result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/PolyglotReader"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
CONFIG_PATH="$PROJECT_DIR/app/src/main/res/xml/locales_config.xml"
MAIN_ACTIVITY_PATH="$PROJECT_DIR/app/src/main/java/com/example/polyglot/MainActivity.kt"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Capture File Contents
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
fi

CONFIG_CONTENT=""
CONFIG_EXISTS="false"
if [ -f "$CONFIG_PATH" ]; then
    CONFIG_EXISTS="true"
    CONFIG_CONTENT=$(cat "$CONFIG_PATH")
fi

MAIN_ACTIVITY_CONTENT=""
if [ -f "$MAIN_ACTIVITY_PATH" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$MAIN_ACTIVITY_PATH")
fi

# 3. Attempt Build (to verify correctness)
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    # Run assembleDebug
    if su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > /tmp/build.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
else
    echo "gradlew not found, skipping build check"
fi

# 4. Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

MANIFEST_JSON=$(escape_json "$MANIFEST_CONTENT")
CONFIG_JSON=$(escape_json "$CONFIG_CONTENT")
MAIN_ACTIVITY_JSON=$(escape_json "$MAIN_ACTIVITY_CONTENT")

# 5. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "manifest_content": $MANIFEST_JSON,
    "config_exists": $CONFIG_EXISTS,
    "config_content": $CONFIG_JSON,
    "main_activity_content": $MAIN_ACTIVITY_JSON,
    "build_success": $BUILD_SUCCESS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete."