#!/bin/bash
echo "=== Exporting task results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
SRC_PKG_DIR="$PROJECT_DIR/src/com/dataprocessor"
BIN_DIR="$PROJECT_DIR/bin"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Compile Check (run javac inside container to verify compilation)
# We use the classpath logic manually since we are not inside Eclipse builder here
echo "Checking compilation..."
mkdir -p "$BIN_DIR"
COMPILE_OUTPUT=$(javac -d "$BIN_DIR" -sourcepath "$PROJECT_DIR/src" "$SRC_PKG_DIR"/*.java 2>&1 || true)
COMPILE_EXIT_CODE=$?

if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    PROJECT_COMPILES="true"
else
    PROJECT_COMPILES="false"
fi

# 3. Read File Contents for Verifier Regex Checks
read_file_content() {
    if [ -f "$1" ]; then
        # Escape for JSON: backslashes, newlines, quotes
        cat "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
    else
        echo "null"
    fi
}

CONTENT_FILEPROCESSOR=$(read_file_content "$SRC_PKG_DIR/FileProcessor.java")
CONTENT_DBCONNECTOR=$(read_file_content "$SRC_PKG_DIR/DatabaseConnector.java")
CONTENT_CONFIGPARSER=$(read_file_content "$SRC_PKG_DIR/ConfigParser.java")
CONTENT_APP=$(read_file_content "$SRC_PKG_DIR/App.java")

# 4. Check modification times (Anti-gaming: files must be modified after start)
check_modified() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

MOD_FILEPROCESSOR=$(check_modified "$SRC_PKG_DIR/FileProcessor.java")
MOD_DBCONNECTOR=$(check_modified "$SRC_PKG_DIR/DatabaseConnector.java")
MOD_CONFIGPARSER=$(check_modified "$SRC_PKG_DIR/ConfigParser.java")
MOD_APP=$(check_modified "$SRC_PKG_DIR/App.java")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "compilation_success": $PROJECT_COMPILES,
    "compilation_output": $(echo "$COMPILE_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "files": {
        "FileProcessor.java": {
            "content": $CONTENT_FILEPROCESSOR,
            "modified": $MOD_FILEPROCESSOR
        },
        "DatabaseConnector.java": {
            "content": $CONTENT_DBCONNECTOR,
            "modified": $MOD_DBCONNECTOR
        },
        "ConfigParser.java": {
            "content": $CONTENT_CONFIGPARSER,
            "modified": $MOD_CONFIGPARSER
        },
        "App.java": {
            "content": $CONTENT_APP,
            "modified": $MOD_APP
        }
    },
    "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="