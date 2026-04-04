#!/bin/bash
set -e

echo "=== Exporting localize_string_resources result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/AndroidStudioProjects/NoteKeeper"
RES_DIR="$PROJECT_DIR/app/src/main/res"

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Check Files ---
ES_FILE="$RES_DIR/values-es/strings.xml"
FR_FILE="$RES_DIR/values-fr/strings.xml"

ES_EXISTS="false"
FR_EXISTS="false"
ES_MTIME="0"
FR_MTIME="0"

if [ -f "$ES_FILE" ]; then
    ES_EXISTS="true"
    ES_MTIME=$(stat -c %Y "$ES_FILE" 2>/dev/null || echo "0")
fi

if [ -f "$FR_FILE" ]; then
    FR_EXISTS="true"
    FR_MTIME=$(stat -c %Y "$FR_FILE" 2>/dev/null || echo "0")
fi

# --- Check Build Status ---
BUILD_SUCCESS="false"
GRADLE_OUTPUT=""

if [ -f "$PROJECT_DIR/gradlew" ]; then
    echo "Running gradle assembleDebug..."
    cd "$PROJECT_DIR"
    
    # Ensure wrapper permissions
    chmod +x gradlew
    
    # Run build
    if su - ga -c "cd $PROJECT_DIR && export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 && ./gradlew assembleDebug --no-daemon" > /tmp/gradle_build.log 2>&1; then
        BUILD_SUCCESS="true"
    fi
    
    GRADLE_OUTPUT=$(tail -n 20 /tmp/gradle_build.log | base64 -w 0)
else
    GRADLE_OUTPUT=$(echo "gradlew not found" | base64 -w 0)
fi

# --- Helper to safe-read file content ---
read_file_safe() {
    if [ -f "$1" ]; then
        cat "$1" | base64 -w 0
    else
        echo ""
    fi
}

ES_CONTENT=$(read_file_safe "$ES_FILE")
FR_CONTENT=$(read_file_safe "$FR_FILE")

# --- Create JSON ---
cat > /tmp/task_result.json <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "es_file_exists": $ES_EXISTS,
  "fr_file_exists": $FR_EXISTS,
  "es_file_mtime": $ES_MTIME,
  "fr_file_mtime": $FR_MTIME,
  "build_success": $BUILD_SUCCESS,
  "gradle_output_b64": "$GRADLE_OUTPUT",
  "es_content_b64": "$ES_CONTENT",
  "fr_content_b64": "$FR_CONTENT",
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure ga owns the result file so it can be copied out if needed (though root runs export usually)
chown ga:ga /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result saved to /tmp/task_result.json"