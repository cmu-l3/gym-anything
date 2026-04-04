#!/bin/bash
echo "=== Exporting setup_logging_framework result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-app"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Compile project to check validity
echo "Running maven compile..."
COMPILE_SUCCESS="false"
COMPILE_OUTPUT=""
cd "$PROJECT_DIR"
if su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile > /tmp/mvn_output.log 2>&1"; then
    COMPILE_SUCCESS="true"
else
    COMPILE_SUCCESS="false"
fi
COMPILE_OUTPUT=$(tail -n 20 /tmp/mvn_output.log)

# 2. Read file contents
safe_read() {
    if [ -f "$1" ]; then
        cat "$1"
    else
        echo ""
    fi
}

POM_CONTENT=$(safe_read "$PROJECT_DIR/pom.xml")
LOGBACK_CONTENT=$(safe_read "$PROJECT_DIR/src/main/resources/logback.xml")

# Read Java files
APP_CONTENT=$(safe_read "$PROJECT_DIR/src/main/java/com/library/LibraryApp.java")
SERVICE_CONTENT=$(safe_read "$PROJECT_DIR/src/main/java/com/library/service/BookService.java")
REPO_CONTENT=$(safe_read "$PROJECT_DIR/src/main/java/com/library/repository/BookRepository.java")
UTIL_CONTENT=$(safe_read "$PROJECT_DIR/src/main/java/com/library/util/SearchEngine.java")

# 3. Check timestamps (Anti-gaming)
FILES_MODIFIED="false"
# specific check for logback.xml creation
LOGBACK_EXISTS="false"
if [ -f "$PROJECT_DIR/src/main/resources/logback.xml" ]; then
    LOGBACK_EXISTS="true"
    MTIME=$(stat -c %Y "$PROJECT_DIR/src/main/resources/logback.xml")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        FILES_MODIFIED="true"
    fi
fi

# 4. Helper to escape JSON string
escape_json() {
    python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))" 
}

# 5. Construct JSON result
# Note: passing raw content, Python verifier will parse it
cat > /tmp/raw_result.json << EOF
{
    "compile_success": $COMPILE_SUCCESS,
    "compile_output": $(echo "$COMPILE_OUTPUT" | escape_json),
    "logback_exists": $LOGBACK_EXISTS,
    "files_modified": $FILES_MODIFIED,
    "pom_content": $(echo "$POM_CONTENT" | escape_json),
    "logback_content": $(echo "$LOGBACK_CONTENT" | escape_json),
    "java_files": {
        "LibraryApp.java": $(echo "$APP_CONTENT" | escape_json),
        "BookService.java": $(echo "$SERVICE_CONTENT" | escape_json),
        "BookRepository.java": $(echo "$REPO_CONTENT" | escape_json),
        "SearchEngine.java": $(echo "$UTIL_CONTENT" | escape_json)
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/raw_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="