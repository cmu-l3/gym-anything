#!/bin/bash
set -e

echo "=== Exporting create_ant_build results ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="commons-cli"
PROJECT_DIR="/home/ga/eclipse-workspace/$PROJECT_NAME"
BUILD_XML="$PROJECT_DIR/build.xml"
OUTPUT_JAR="$PROJECT_DIR/build/commons-cli.jar"
CLASSES_DIR="$PROJECT_DIR/build/classes"

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Collect File Evidence
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# Check build.xml
BUILD_XML_EXISTS="false"
BUILD_XML_CONTENT=""
if [ -f "$BUILD_XML" ]; then
    BUILD_XML_EXISTS="true"
    BUILD_XML_CONTENT=$(cat "$BUILD_XML" | base64 -w 0) 
fi

# Check JAR file
JAR_EXISTS="false"
JAR_SIZE="0"
JAR_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_JAR" ]; then
    JAR_EXISTS="true"
    JAR_SIZE=$(stat -c %s "$OUTPUT_JAR")
    JAR_MTIME=$(stat -c %Y "$OUTPUT_JAR")
    
    if [ "$JAR_MTIME" -ge "$TASK_START" ]; then
        JAR_CREATED_DURING_TASK="true"
    fi
fi

# Check Compilation (Class files)
CLASS_FILES_COUNT=0
if [ -d "$CLASSES_DIR" ]; then
    CLASS_FILES_COUNT=$(find "$CLASSES_DIR" -name "*.class" | wc -l)
fi

# 3. Check Eclipse Logs for Ant Execution Evidence
# Eclipse stores Ant build history in logs or console output is transient.
# We'll rely on file artifacts (jars/classes) and VLM for execution verification.
# However, we can check if the output directory was recently created.
BUILD_DIR_EXISTS="false"
if [ -d "$PROJECT_DIR/build" ]; then
    BUILD_DIR_EXISTS="true"
fi

# 4. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $CURRENT_TIME,
    "build_xml_exists": $BUILD_XML_EXISTS,
    "build_xml_content_base64": "$BUILD_XML_CONTENT",
    "jar_exists": $JAR_EXISTS,
    "jar_size_bytes": $JAR_SIZE,
    "jar_created_during_task": $JAR_CREATED_DURING_TASK,
    "class_files_count": $CLASS_FILES_COUNT,
    "build_dir_exists": $BUILD_DIR_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result safely
write_json_result "$(cat $TEMP_JSON)" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="