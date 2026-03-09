#!/bin/bash
echo "=== Exporting recover_code_local_history result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/fintech-core"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/fintech/core/TransactionValidator.java"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end.png

# 2. Check if file content is restored
FILE_CONTENT=""
if [ -f "$TARGET_FILE" ]; then
    FILE_CONTENT=$(cat "$TARGET_FILE" 2>/dev/null)
else
    echo "WARNING: Target file not found!"
fi

# 3. Compile the project to verify syntax
COMPILE_SUCCESS="false"
COMPILE_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    echo "Running compilation..."
    cd "$PROJECT_DIR"
    COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile 2>&1)
    if [ $? -eq 0 ]; then
        COMPILE_SUCCESS="true"
    fi
fi

# 4. Check for 'git' usage (anti-gaming check)
# If the user initialized git to try to solve it (won't work, but good to know)
GIT_USED="false"
if [ -d "$PROJECT_DIR/.git" ]; then
    GIT_USED="true"
fi

# 5. Prepare JSON Result
# Escape content for JSON safely
CONTENT_ESCAPED=$(echo "$FILE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_ESCAPED=$(echo "$COMPILE_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Save result
cat > /tmp/task_result.json << EOF
{
    "file_content": $CONTENT_ESCAPED,
    "compile_success": $COMPILE_SUCCESS,
    "compile_output": $OUTPUT_ESCAPED,
    "git_used": $GIT_USED,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="