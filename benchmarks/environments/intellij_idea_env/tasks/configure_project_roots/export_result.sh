#!/bin/bash
echo "=== Exporting configure_project_roots result ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="LegacyInventory"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# 1. Take Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Check for Build Artifacts (Compiled Classes)
# IntelliJ default output path for modules is usually out/production/<ModuleName>
# We search for the specific class file expected.
CLASS_FILE="$PROJECT_DIR/out/production/$PROJECT_NAME/com/inventory/Main.java" # Mistake in variable name, fixing path logic below
EXPECTED_CLASS_PATH="$PROJECT_DIR/out/production/$PROJECT_NAME/com/inventory/Main.class"
TEST_CLASS_PATH="$PROJECT_DIR/out/test/$PROJECT_NAME/com/inventory/InventoryTest.class"

MAIN_CLASS_EXISTS="false"
TEST_CLASS_EXISTS="false"
MAIN_CLASS_TIMESTAMP=0

if [ -f "$EXPECTED_CLASS_PATH" ]; then
    MAIN_CLASS_EXISTS="true"
    MAIN_CLASS_TIMESTAMP=$(stat -c %Y "$EXPECTED_CLASS_PATH")
fi

if [ -f "$TEST_CLASS_PATH" ]; then
    TEST_CLASS_EXISTS="true"
fi

# 3. Capture Module Configuration (.iml file)
# The .iml file contains the configuration for roots and dependencies.
IML_FILE=$(find "$PROJECT_DIR" -maxdepth 2 -name "*.iml" | head -n 1)
IML_CONTENT=""
if [ -f "$IML_FILE" ]; then
    IML_CONTENT=$(cat "$IML_FILE")
fi

# Also check .idea/libraries if dependencies are stored there
LIBRARIES_CONTENT=""
if [ -d "$PROJECT_DIR/.idea/libraries" ]; then
    for lib in "$PROJECT_DIR/.idea/libraries"/*.xml; do
        if [ -f "$lib" ]; then
            LIBRARIES_CONTENT+="$(cat "$lib")\n"
        fi
    done
fi

# 4. Check Task Start Time for Anti-Gaming
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$MAIN_CLASS_TIMESTAMP" -gt "$TASK_START_TIME" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# 5. Create Result JSON
# Python used for safe JSON string escaping
RESULT_JSON=$(python3 << PYTHON_EOF
import json
import os
import sys

output = {
    "main_class_exists": $MAIN_CLASS_EXISTS,
    "test_class_exists": $TEST_CLASS_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "iml_content": """$IML_CONTENT""",
    "libraries_content": """$LIBRARIES_CONTENT""",
    "screenshot_path": "/tmp/task_end.png"
}
print(json.dumps(output))
PYTHON_EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="