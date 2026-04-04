#!/bin/bash
echo "=== Exporting implement_android12_splash_screen result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/SunriseApp"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Build Status (CRITICAL)
echo "Running build check..."
BUILD_SUCCESS="false"
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run assembleDebug to verify compilation
    # We ignore lint errors to focus on successful compilation
    su - ga -c "cd $PROJECT_DIR; export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleDebug -x lint --no-daemon" > /tmp/gradle_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
        echo "Build succeeded"
    else
        echo "Build failed"
    fi
fi

# 3. Read Files Content
BUILD_GRADLE_CONTENT=""
if [ -f "$PROJECT_DIR/app/build.gradle.kts" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$PROJECT_DIR/app/build.gradle.kts")
fi

THEMES_XML_CONTENT=""
if [ -f "$PROJECT_DIR/app/src/main/res/values/themes.xml" ]; then
    THEMES_XML_CONTENT=$(cat "$PROJECT_DIR/app/src/main/res/values/themes.xml")
fi

MANIFEST_CONTENT=""
if [ -f "$PROJECT_DIR/app/src/main/AndroidManifest.xml" ]; then
    MANIFEST_CONTENT=$(cat "$PROJECT_DIR/app/src/main/AndroidManifest.xml")
fi

MAIN_ACTIVITY_CONTENT=""
if [ -f "$PROJECT_DIR/app/src/main/java/com/example/sunriseapp/MainActivity.kt" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$PROJECT_DIR/app/src/main/java/com/example/sunriseapp/MainActivity.kt")
fi

GRADLE_LOG=""
if [ -f /tmp/gradle_output.log ]; then
    GRADLE_LOG=$(tail -n 50 /tmp/gradle_output.log)
fi

# 4. Helper to escape JSON string safely
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

# 5. Create Result JSON
# Using python one-liner for cleaner JSON generation to avoid quoting hell in bash
cat << EOF > /tmp/json_gen.py
import json
import sys

data = {
    "build_success": $BUILD_SUCCESS,
    "build_gradle_content": $(escape_json "$BUILD_GRADLE_CONTENT"),
    "themes_xml_content": $(escape_json "$THEMES_XML_CONTENT"),
    "manifest_content": $(escape_json "$MANIFEST_CONTENT"),
    "main_activity_content": $(escape_json "$MAIN_ACTIVITY_CONTENT"),
    "gradle_log": $(escape_json "$GRADLE_LOG"),
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date +%s)"
}
print(json.dumps(data, indent=2))
EOF

python3 /tmp/json_gen.py > /tmp/task_result.json

# Cleanup
rm -f /tmp/json_gen.py
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="