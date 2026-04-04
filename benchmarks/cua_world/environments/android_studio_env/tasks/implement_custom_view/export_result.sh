#!/bin/bash
echo "=== Exporting implement_custom_view result ==="

source /workspace/scripts/task_utils.sh

# Record paths
PROJECT_DIR="/home/ga/AndroidStudioProjects/LogisticsDashboard"
ATTRS_FILE="$PROJECT_DIR/app/src/main/res/values/attrs.xml"
VIEW_FILE="$PROJECT_DIR/app/src/main/java/com/example/logisticsdashboard/views/StatusDotView.kt"
LAYOUT_FILE="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ------------------------------------------------------------------
# 1. Check for file existence and modifications
# ------------------------------------------------------------------

ATTRS_EXISTS="false"
ATTRS_CONTENT=""
if [ -f "$ATTRS_FILE" ]; then
    ATTRS_EXISTS="true"
    ATTRS_CONTENT=$(cat "$ATTRS_FILE" 2>/dev/null)
fi

VIEW_EXISTS="false"
VIEW_CONTENT=""
if [ -f "$VIEW_FILE" ]; then
    VIEW_EXISTS="true"
    VIEW_CONTENT=$(cat "$VIEW_FILE" 2>/dev/null)
fi

LAYOUT_EXISTS="false"
LAYOUT_CONTENT=""
if [ -f "$LAYOUT_FILE" ]; then
    LAYOUT_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$LAYOUT_FILE" 2>/dev/null)
fi

# ------------------------------------------------------------------
# 2. Attempt Build Verification
# ------------------------------------------------------------------
BUILD_SUCCESS="false"
GRADLE_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running build verification..."
    cd "$PROJECT_DIR"
    
    # We use 'assembleDebug' to verify full compilation including resources
    # Using 'su - ga' to ensure environment variables are loaded
    BUILD_LOG=$(mktemp)
    
    # Timeout command to prevent hanging indefinitely
    timeout 300s su - ga -c "cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" > "$BUILD_LOG" 2>&1
    RET_CODE=$?
    
    GRADLE_OUTPUT=$(cat "$BUILD_LOG" | tail -n 50)
    rm -f "$BUILD_LOG"
    
    if [ $RET_CODE -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# ------------------------------------------------------------------
# 3. Prepare JSON Result
# ------------------------------------------------------------------

# Helper to escape JSON strings
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

ATTRS_JSON=$(escape_json "$ATTRS_CONTENT")
VIEW_JSON=$(escape_json "$VIEW_CONTENT")
LAYOUT_JSON=$(escape_json "$LAYOUT_CONTENT")
GRADLE_JSON=$(escape_json "$GRADLE_OUTPUT")

cat > /tmp/temp_result.json <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "attrs_exists": $ATTRS_EXISTS,
    "attrs_content": $ATTRS_JSON,
    "view_exists": $VIEW_EXISTS,
    "view_content": $VIEW_JSON,
    "layout_exists": $LAYOUT_EXISTS,
    "layout_content": $LAYOUT_JSON,
    "build_success": $BUILD_SUCCESS,
    "gradle_output": $GRADLE_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f /tmp/temp_result.json

echo "Export complete. Result saved to /tmp/task_result.json"