#!/bin/bash
echo "=== Exporting remediate_accessibility_violations result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/AccessAll"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_login.xml"
STRINGS_FILE="$PROJECT_DIR/app/src/main/res/values/strings.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Read file contents
LAYOUT_CONTENT=""
STRINGS_CONTENT=""
FILE_MODIFIED="false"

if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE")
    # Check modification time
    LAYOUT_MTIME=$(stat -c %Y "$LAYOUT_FILE" 2>/dev/null || echo "0")
    if [ "$LAYOUT_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

if [ -f "$STRINGS_FILE" ]; then
    STRINGS_CONTENT=$(cat "$STRINGS_FILE")
fi

# 2. Attempt Build (Validation of XML correctness)
BUILD_SUCCESS="false"
BUILD_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running build check..."
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # Run assembleDebug to check XML validity
    # We use a timeout to prevent hanging if gradle downloads take too long
    timeout 300s ./gradlew assembleDebug -Pandroid.injected.build.model.only.versioned=3 \
        -Dorg.gradle.jvmargs="-Xmx1g" > /tmp/gradle_build.log 2>&1
    
    EXIT_CODE=$?
    if [ $EXIT_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    BUILD_OUTPUT=$(tail -n 50 /tmp/gradle_build.log)
else
    echo "gradlew not found"
fi

# 3. Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

LAYOUT_ESCAPED=$(escape_json "$LAYOUT_CONTENT")
STRINGS_ESCAPED=$(escape_json "$STRINGS_CONTENT")
BUILD_OUTPUT_ESCAPED=$(escape_json "$BUILD_OUTPUT")

# 4. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "layout_exists": $([ -f "$LAYOUT_FILE" ] && echo "true" || echo "false"),
    "layout_content": $LAYOUT_ESCAPED,
    "strings_content": $STRINGS_ESCAPED,
    "file_modified": $FILE_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"