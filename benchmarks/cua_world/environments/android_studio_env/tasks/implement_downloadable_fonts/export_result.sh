#!/bin/bash
echo "=== Exporting implement_downloadable_fonts result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/QuoteApp"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check for Font File
FONT_FILE="$RES_DIR/font/pacifico.xml"
FONT_EXISTS="false"
FONT_IS_XML="false"
FONT_CONTENT=""

if [ -f "$FONT_FILE" ]; then
    FONT_EXISTS="true"
    # Check if it's actually XML (not binary)
    if file "$FONT_FILE" | grep -q "XML"; then
        FONT_IS_XML="true"
        FONT_CONTENT=$(cat "$FONT_FILE")
    fi
fi

# 3. Check Manifest
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
MANIFEST_CONTENT=""
if [ -f "$MANIFEST_FILE" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_FILE")
fi

# 4. Check Styles/Themes
THEMES_FILE="$RES_DIR/values/themes.xml"
STYLES_FILE="$RES_DIR/values/styles.xml"
THEMES_CONTENT=""
STYLES_CONTENT=""

if [ -f "$THEMES_FILE" ]; then
    THEMES_CONTENT=$(cat "$THEMES_FILE")
fi
if [ -f "$STYLES_FILE" ]; then
    STYLES_CONTENT=$(cat "$STYLES_FILE")
fi

# 5. Check Layout
LAYOUT_FILE="$RES_DIR/layout/activity_main.xml"
LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
fi

# 6. Try to build
BUILD_SUCCESS="false"
echo "Attempting Gradle build..."
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    # We suppress output to keep the log clean, but capture exit code
    if ./gradlew assembleDebug --no-daemon > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
fi

# 7. Helper to escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"
}

FONT_JSON=$(escape_json "$FONT_CONTENT")
MANIFEST_JSON=$(escape_json "$MANIFEST_CONTENT")
THEMES_JSON=$(escape_json "$THEMES_CONTENT")
STYLES_JSON=$(escape_json "$STYLES_CONTENT")
LAYOUT_JSON=$(escape_json "$LAYOUT_CONTENT")

# 8. Create JSON result
# Note: We use a temp file and move it to avoid permission issues if executed as root
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "font_exists": $FONT_EXISTS,
    "font_is_xml": $FONT_IS_XML,
    "font_content": $FONT_JSON,
    "manifest_content": $MANIFEST_JSON,
    "themes_content": $THEMES_JSON,
    "styles_content": $STYLES_JSON,
    "layout_content": $LAYOUT_JSON,
    "build_success": $BUILD_SUCCESS,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON"

echo "=== Export complete ==="