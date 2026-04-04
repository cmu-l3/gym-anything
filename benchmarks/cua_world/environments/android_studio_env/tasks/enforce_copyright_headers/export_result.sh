#!/bin/bash
echo "=== Exporting Enforce Copyright Headers result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_DIR="/home/ga/AndroidStudioProjects/TechCorpApp"
IDEA_COPYRIGHT_DIR="$PROJECT_DIR/.idea/copyright"
MAIN_ACTIVITY="$PROJECT_DIR/app/src/main/java/com/example/techcorpapp/MainActivity.kt"
LAYOUT_XML="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# 1. Check for Copyright Profile Config
PROFILE_EXISTS="false"
PROFILE_CONTENT=""
PROFILE_FILENAME=""

if [ -d "$IDEA_COPYRIGHT_DIR" ]; then
    # Look for any XML file that isn't profiles_settings.xml (which just stores the mapping)
    # The actual profile definition usually takes the name of the profile
    FOUND_PROFILE=$(find "$IDEA_COPYRIGHT_DIR" -name "*.xml" ! -name "profiles_settings.xml" | head -n 1)
    
    if [ -n "$FOUND_PROFILE" ]; then
        PROFILE_EXISTS="true"
        PROFILE_FILENAME=$(basename "$FOUND_PROFILE")
        PROFILE_CONTENT=$(cat "$FOUND_PROFILE")
    fi
fi

# 2. Check MainActivity.kt
KT_EXISTS="false"
KT_MODIFIED="false"
KT_CONTENT=""

if [ -f "$MAIN_ACTIVITY" ]; then
    KT_EXISTS="true"
    KT_CONTENT=$(cat "$MAIN_ACTIVITY")
    
    KT_MTIME=$(stat -c %Y "$MAIN_ACTIVITY")
    if [ "$KT_MTIME" -gt "$TASK_START" ]; then
        KT_MODIFIED="true"
    fi
fi

# 3. Check activity_main.xml
XML_EXISTS="false"
XML_MODIFIED="false"
XML_CONTENT=""

if [ -f "$LAYOUT_XML" ]; then
    XML_EXISTS="true"
    XML_CONTENT=$(cat "$LAYOUT_XML")
    
    XML_MTIME=$(stat -c %Y "$LAYOUT_XML")
    if [ "$XML_MTIME" -gt "$TASK_START" ]; then
        XML_MODIFIED="true"
    fi
fi

# 4. Check App State
APP_RUNNING=$(pgrep -f "studio" > /dev/null && echo "true" || echo "false")

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""'
}

PROFILE_CONTENT_ESCAPED=$(escape_json "$PROFILE_CONTENT")
KT_CONTENT_ESCAPED=$(escape_json "$KT_CONTENT")
XML_CONTENT_ESCAPED=$(escape_json "$XML_CONTENT")

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "profile_exists": $PROFILE_EXISTS,
    "profile_filename": "$PROFILE_FILENAME",
    "profile_content": $PROFILE_CONTENT_ESCAPED,
    "kotlin_file_exists": $KT_EXISTS,
    "kotlin_file_modified": $KT_MODIFIED,
    "kotlin_content": $KT_CONTENT_ESCAPED,
    "xml_file_exists": $XML_EXISTS,
    "xml_file_modified": $XML_MODIFIED,
    "xml_content": $XML_CONTENT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"