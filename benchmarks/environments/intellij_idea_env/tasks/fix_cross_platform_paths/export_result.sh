#!/bin/bash
echo "=== Exporting fix_cross_platform_paths result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/path-issues"
OUTPUT_REPORT="$PROJECT_DIR/output/report.txt"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Attempt to compile and run the project (Verification Step)
echo "Running application to verify fix..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile exec:java 2>&1)
EXIT_CODE=$?

echo "Exit Code: $EXIT_CODE" > /tmp/run_exit_code.txt
echo "$BUILD_OUTPUT" > /tmp/run_output.log

# 2. Check for output file
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$OUTPUT_REPORT" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$OUTPUT_REPORT")
fi

# 3. Read Source Code for Static Analysis
MAIN_SRC=""
CONFIG_SRC=""
if [ -f "$PROJECT_DIR/src/main/java/com/example/paths/Main.java" ]; then
    MAIN_SRC=$(cat "$PROJECT_DIR/src/main/java/com/example/paths/Main.java")
fi
if [ -f "$PROJECT_DIR/src/main/java/com/example/paths/ConfigLoader.java" ]; then
    CONFIG_SRC=$(cat "$PROJECT_DIR/src/main/java/com/example/paths/ConfigLoader.java")
fi

# 4. Check modification timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_MODIFIED="false"

MAIN_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/example/paths/Main.java" 2>/dev/null || echo "0")
CONFIG_MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/java/com/example/paths/ConfigLoader.java" 2>/dev/null || echo "0")

if [ "$MAIN_MTIME" -gt "$TASK_START" ] || [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED="true"
fi

# 5. Prepare JSON
# Python script to safely escape JSON strings
python3 -c "
import json
import os

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r', errors='replace') as f:
            return f.read()
    return ''

result = {
    'run_exit_code': int(read_file('/tmp/run_exit_code.txt').strip() or 1),
    'run_output': read_file('/tmp/run_output.log')[-2000:],
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_content': '$REPORT_CONTENT',
    'main_source': '''$MAIN_SRC''',
    'config_source': '''$CONFIG_SRC''',
    'files_modified': '$FILES_MODIFIED' == 'true',
    'timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="