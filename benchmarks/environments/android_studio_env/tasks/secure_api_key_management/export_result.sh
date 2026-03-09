#!/bin/bash
echo "=== Exporting secure_api_key_management result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/CityWeather"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
LOCAL_PROPS="$PROJECT_DIR/local.properties"
BUILD_GRADLE="$PROJECT_DIR/app/build.gradle.kts"
SERVICE_FILE="$PROJECT_DIR/app/src/main/java/com/example/cityweather/network/WeatherService.kt"

# Read File Contents
LOCAL_PROPS_CONTENT=""
if [ -f "$LOCAL_PROPS" ]; then
    LOCAL_PROPS_CONTENT=$(cat "$LOCAL_PROPS")
fi

BUILD_GRADLE_CONTENT=""
if [ -f "$BUILD_GRADLE" ]; then
    BUILD_GRADLE_CONTENT=$(cat "$BUILD_GRADLE")
fi

SERVICE_FILE_CONTENT=""
if [ -f "$SERVICE_FILE" ]; then
    SERVICE_FILE_CONTENT=$(cat "$SERVICE_FILE")
fi

# Attempt Build
BUILD_SUCCESS="false"
BUILD_OUTPUT=""
if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle build verification..."
    cd "$PROJECT_DIR"
    chmod +x gradlew 2>/dev/null || true
    
    # We run assembleDebug to trigger BuildConfig generation
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    ANDROID_HOME=/opt/android-sdk \
    ./gradlew assembleDebug --no-daemon > /tmp/gradle_build_output.log 2>&1
    
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 20 /tmp/gradle_build_output.log)
fi

# Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '"%s"' "$1"
}

LOCAL_PROPS_JSON=$(escape_json "$LOCAL_PROPS_CONTENT")
BUILD_GRADLE_JSON=$(escape_json "$BUILD_GRADLE_CONTENT")
SERVICE_FILE_JSON=$(escape_json "$SERVICE_FILE_CONTENT")
BUILD_OUTPUT_JSON=$(escape_json "$BUILD_OUTPUT")

# Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "local_properties_exists": $([ -f "$LOCAL_PROPS" ] && echo "true" || echo "false"),
    "build_gradle_exists": $([ -f "$BUILD_GRADLE" ] && echo "true" || echo "false"),
    "service_file_exists": $([ -f "$SERVICE_FILE" ] && echo "true" || echo "false"),
    "local_properties_content": $LOCAL_PROPS_JSON,
    "build_gradle_content": $BUILD_GRADLE_JSON,
    "service_file_content": $SERVICE_FILE_JSON,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "=== Export complete ==="