#!/bin/bash
echo "=== Exporting refactor_extract_class result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
PROJECT_DIR="/home/ga/eclipse-workspace/MedTechCore"
ORIGINAL_FILE="$PROJECT_DIR/src/main/java/com/medtech/device/RadiationTreatmentUnit.java"
NEW_FILE="$PROJECT_DIR/src/main/java/com/medtech/device/NetworkConfiguration.java"
LOG_FILE="/tmp/maven_test_result.log"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run Maven tests to verify compilation and functionality
# We run this inside the container where Maven and Java are correctly set up
echo "Running Maven tests..."
cd "$PROJECT_DIR"
mvn clean test > "$LOG_FILE" 2>&1
MVN_EXIT_CODE=$?

# 3. Read File Contents
ORIGINAL_CONTENT=""
if [ -f "$ORIGINAL_FILE" ]; then
    ORIGINAL_CONTENT=$(cat "$ORIGINAL_FILE")
fi

NEW_CONTENT=""
if [ -f "$NEW_FILE" ]; then
    NEW_CONTENT=$(cat "$NEW_FILE")
fi

MAVEN_LOG_CONTENT=$(head -n 200 "$LOG_FILE" && echo "..." && tail -n 50 "$LOG_FILE")

# 4. JSON Export
# Helper to escape JSON strings
escape_json() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))"
}

ESC_ORIGINAL=$(echo "$ORIGINAL_CONTENT" | escape_json)
ESC_NEW=$(echo "$NEW_CONTENT" | escape_json)
ESC_LOG=$(echo "$MAVEN_LOG_CONTENT" | escape_json)

RESULT_JSON=$(cat << EOF
{
    "maven_exit_code": $MVN_EXIT_CODE,
    "original_exists": $([ -f "$ORIGINAL_FILE" ] && echo "true" || echo "false"),
    "new_file_exists": $([ -f "$NEW_FILE" ] && echo "true" || echo "false"),
    "original_content": $ESC_ORIGINAL,
    "new_content": $ESC_NEW,
    "maven_log": $ESC_LOG,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Safe write
write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "Maven Exit Code: $MVN_EXIT_CODE"
echo "=== Export Complete ==="