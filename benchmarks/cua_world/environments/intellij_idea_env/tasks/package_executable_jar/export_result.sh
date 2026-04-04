#!/bin/bash
echo "=== Exporting package_executable_jar result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/csv-stats"
JAR_PATH="$PROJECT_DIR/target/csv-stats-1.0.jar"
CSV_PATH="$PROJECT_DIR/src/main/resources/sample_data.csv"

# Take final screenshot
take_screenshot /tmp/task_end.png

# --- Collect Evidence ---

# 1. JAR Existence & Timestamp
JAR_EXISTS="false"
JAR_SIZE="0"
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$JAR_PATH" ]; then
    JAR_EXISTS="true"
    JAR_SIZE=$(stat -c %s "$JAR_PATH" 2>/dev/null || echo "0")
    JAR_MTIME=$(stat -c %Y "$JAR_PATH" 2>/dev/null || echo "0")
    
    if [ "$JAR_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 2. Manifest Inspection (Main-Class)
MANIFEST_CONTENT=""
HAS_MAIN_CLASS="false"
if [ "$JAR_EXISTS" = "true" ]; then
    # Extract manifest to stdout
    MANIFEST_CONTENT=$(unzip -p "$JAR_PATH" META-INF/MANIFEST.MF 2>/dev/null || echo "")
    if echo "$MANIFEST_CONTENT" | grep -q "Main-Class: com.csvstats.App"; then
        HAS_MAIN_CLASS="true"
    fi
fi

# 3. Dependency Bundling (Shading) Check
# Check if Commons CSV classes are inside the JAR
HAS_DEPENDENCIES="false"
JAR_LISTING=""
if [ "$JAR_EXISTS" = "true" ]; then
    JAR_LISTING=$(jar tf "$JAR_PATH" 2>/dev/null || unzip -l "$JAR_PATH" 2>/dev/null)
    if echo "$JAR_LISTING" | grep -q "org/apache/commons/csv/CSVFormat.class"; then
        HAS_DEPENDENCIES="true"
    fi
fi

# 4. Execution Test
EXECUTION_SUCCESS="false"
EXECUTION_OUTPUT=""
if [ "$JAR_EXISTS" = "true" ]; then
    # Run the JAR
    EXECUTION_OUTPUT=$(java -jar "$JAR_PATH" "$CSV_PATH" 2>&1)
    EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        EXECUTION_SUCCESS="true"
    fi
fi

# 5. POM Content (Secondary check)
POM_CONTENT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    POM_CONTENT=$(cat "$PROJECT_DIR/pom.xml")
fi

# Encode for JSON
MAN_ESCAPED=$(echo "$MANIFEST_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
OUT_ESCAPED=$(echo "$EXECUTION_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
POM_ESCAPED=$(echo "$POM_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

RESULT_JSON=$(cat << EOF
{
    "jar_exists": $JAR_EXISTS,
    "jar_size_bytes": $JAR_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "has_main_class_manifest": $HAS_MAIN_CLASS,
    "has_bundled_dependencies": $HAS_DEPENDENCIES,
    "execution_success": $EXECUTION_SUCCESS,
    "execution_output": $OUT_ESCAPED,
    "manifest_content": $MAN_ESCAPED,
    "pom_content": $POM_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="