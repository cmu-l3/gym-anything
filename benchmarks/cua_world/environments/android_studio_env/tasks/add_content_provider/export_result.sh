#!/bin/bash
echo "=== Exporting add_content_provider result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/NotesApp"
PROVIDER_DIR="$PROJECT_DIR/app/src/main/java/com/example/notesapp/provider"
MANIFEST_PATH="$PROJECT_DIR/app/src/main/AndroidManifest.xml"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize result variables
CONTRACT_EXISTS="false"
PROVIDER_EXISTS="false"
MANIFEST_MODIFIED="false"
BUILD_SUCCESS="false"

CONTRACT_CONTENT=""
PROVIDER_CONTENT=""
MANIFEST_CONTENT=""
GRADLE_OUTPUT=""

# 1. Check Files
if [ -f "$PROVIDER_DIR/NoteContract.kt" ]; then
    CONTRACT_EXISTS="true"
    CONTRACT_CONTENT=$(cat "$PROVIDER_DIR/NoteContract.kt")
fi

if [ -f "$PROVIDER_DIR/NoteContentProvider.kt" ]; then
    PROVIDER_EXISTS="true"
    PROVIDER_CONTENT=$(cat "$PROVIDER_DIR/NoteContentProvider.kt")
fi

if [ -f "$MANIFEST_PATH" ]; then
    MANIFEST_CONTENT=$(cat "$MANIFEST_PATH")
    # Simple check if provider was added
    if grep -q "provider" "$MANIFEST_PATH"; then
        MANIFEST_MODIFIED="true"
    fi
fi

# 2. Check Timestamps (Anti-Gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTRACT_MTIME=$(stat -c %Y "$PROVIDER_DIR/NoteContract.kt" 2>/dev/null || echo "0")
PROVIDER_MTIME=$(stat -c %Y "$PROVIDER_DIR/NoteContentProvider.kt" 2>/dev/null || echo "0")
MANIFEST_MTIME=$(stat -c %Y "$MANIFEST_PATH" 2>/dev/null || echo "0")

CONTRACT_NEW=$( [ "$CONTRACT_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false" )
PROVIDER_NEW=$( [ "$PROVIDER_MTIME" -gt "$TASK_START" ] && echo "true" || echo "false" )

# 3. Attempt Build
echo "Running validation build..."
if [ -f "$PROJECT_DIR/gradlew" ]; then
    cd "$PROJECT_DIR"
    chmod +x gradlew
    
    # We use assembleDebug to verify everything compiles
    GRADLE_LOG=$(su - ga -c "cd $PROJECT_DIR && ./gradlew assembleDebug --no-daemon" 2>&1)
    GRADLE_EXIT=$?
    
    if [ $GRADLE_EXIT -eq 0 ]; then
        BUILD_SUCCESS="true"
    fi
    
    # Capture last 100 lines of log
    GRADLE_OUTPUT=$(echo "$GRADLE_LOG" | tail -n 100)
fi

# 4. Prepare JSON output
# Helper to escape JSON string
escape_json() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' 2>/dev/null || echo '""'
}

CONTRACT_JSON=$(escape_json "$CONTRACT_CONTENT")
PROVIDER_JSON=$(escape_json "$PROVIDER_CONTENT")
MANIFEST_JSON=$(escape_json "$MANIFEST_CONTENT")
LOG_JSON=$(escape_json "$GRADLE_OUTPUT")

cat > /tmp/temp_result.json <<EOF
{
    "contract_exists": $CONTRACT_EXISTS,
    "provider_exists": $PROVIDER_EXISTS,
    "manifest_modified": $MANIFEST_MODIFIED,
    "contract_created_during_task": $CONTRACT_NEW,
    "provider_created_during_task": $PROVIDER_NEW,
    "build_success": $BUILD_SUCCESS,
    "contract_content": $CONTRACT_JSON,
    "provider_content": $PROVIDER_JSON,
    "manifest_content": $MANIFEST_JSON,
    "gradle_log": $LOG_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safely move result
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"