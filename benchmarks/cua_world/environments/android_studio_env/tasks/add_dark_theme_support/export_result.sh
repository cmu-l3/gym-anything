#!/bin/bash
set -e
echo "=== Exporting add_dark_theme_support result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/WeatherApp"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Initialize contents
THEMES_CONTENT=""
NIGHT_COLORS_CONTENT=""
LIGHT_COLORS_CONTENT=""
MAIN_ACTIVITY_CONTENT=""
NIGHT_COLORS_EXISTS="false"
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

# 1. Read files
if [ -f "$RES_DIR/values/themes.xml" ]; then
    THEMES_CONTENT=$(cat "$RES_DIR/values/themes.xml")
fi

if [ -f "$RES_DIR/values-night/colors.xml" ]; then
    NIGHT_COLORS_CONTENT=$(cat "$RES_DIR/values-night/colors.xml")
    NIGHT_COLORS_EXISTS="true"
fi

if [ -f "$RES_DIR/values/colors.xml" ]; then
    LIGHT_COLORS_CONTENT=$(cat "$RES_DIR/values/colors.xml")
fi

if [ -f "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/MainActivity.kt" ]; then
    MAIN_ACTIVITY_CONTENT=$(cat "$PROJECT_DIR/app/src/main/java/com/example/weatherapp/MainActivity.kt")
fi

# 2. Attempt Build (if wrapper exists)
if [ -x "$PROJECT_DIR/gradlew" ]; then
    echo "Running Gradle build..."
    cd "$PROJECT_DIR"
    
    # Try assembleDebug
    if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 ./gradlew assembleDebug --no-daemon > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 20 /tmp/gradle_build.log 2>/dev/null || echo "No log")
else
    echo "Gradle wrapper not found, skipping CLI build check."
    BUILD_OUTPUT="Gradle wrapper missing"
fi

# 3. Escape for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

THEMES_ESCAPED=$(escape_json "$THEMES_CONTENT")
NIGHT_COLORS_ESCAPED=$(escape_json "$NIGHT_COLORS_CONTENT")
LIGHT_COLORS_ESCAPED=$(escape_json "$LIGHT_COLORS_CONTENT")
MAIN_ACTIVITY_ESCAPED=$(escape_json "$MAIN_ACTIVITY_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# 4. Write JSON
cat > /tmp/task_result.json <<EOF
{
    "themes_content": $THEMES_ESCAPED,
    "night_colors_content": $NIGHT_COLORS_ESCAPED,
    "light_colors_content": $LIGHT_COLORS_ESCAPED,
    "main_activity_content": $MAIN_ACTIVITY_ESCAPED,
    "night_colors_exists": $NIGHT_COLORS_EXISTS,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "timestamp": "$(date +%s)"
}
EOF

# Secure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="