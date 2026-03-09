#!/bin/bash
echo "=== Exporting create_state_list_drawable result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Configuration
PROJECT_DIR="/home/ga/AndroidStudioProjects/LoginUI"
DRAWABLE_PATH="$PROJECT_DIR/app/src/main/res/drawable/login_button_bg.xml"
LAYOUT_PATH="$PROJECT_DIR/app/src/main/res/layout/activity_main.xml"

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Check Drawable
DRAWABLE_EXISTS="false"
DRAWABLE_CONTENT=""
if [ -f "$DRAWABLE_PATH" ]; then
    DRAWABLE_EXISTS="true"
    DRAWABLE_CONTENT=$(cat "$DRAWABLE_PATH" 2>/dev/null)
fi

# Check Layout
LAYOUT_EXISTS="false"
LAYOUT_CONTENT=""
LAYOUT_MODIFIED="false"
if [ -f "$LAYOUT_PATH" ]; then
    LAYOUT_EXISTS="true"
    LAYOUT_CONTENT=$(cat "$LAYOUT_PATH" 2>/dev/null)
    
    # Check modification
    if [ -f /tmp/initial_layout_hash.txt ]; then
        CURRENT_HASH=$(md5sum "$LAYOUT_PATH" | awk '{print $1}')
        INITIAL_HASH=$(cat /tmp/initial_layout_hash.txt | awk '{print $1}')
        if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
            LAYOUT_MODIFIED="true"
        fi
    else
        LAYOUT_MODIFIED="true" # Assume modified if no hash
    fi
fi

# Check if project compiles (optional but good verification)
BUILD_SUCCESS="false"
if [ "$DRAWABLE_EXISTS" = "true" ] && [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Attempting to compile resources..."
    cd "$PROJECT_DIR"
    # We only run processDebugResources to save time compared to full assemble
    timeout 120 ./gradlew processDebugResources > /tmp/gradle_build.log 2>&1
    if [ $? -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
fi

# Escape content for JSON
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || printf '""'
}

DRAWABLE_ESCAPED=$(escape_json "$DRAWABLE_CONTENT")
LAYOUT_ESCAPED=$(escape_json "$LAYOUT_CONTENT")

# Create JSON result
cat > /tmp/task_result.json <<EOF
{
    "drawable_exists": $DRAWABLE_EXISTS,
    "drawable_content": $DRAWABLE_ESCAPED,
    "layout_exists": $LAYOUT_EXISTS,
    "layout_content": $LAYOUT_ESCAPED,
    "layout_modified": $LAYOUT_MODIFIED,
    "build_success": $BUILD_SUCCESS,
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="