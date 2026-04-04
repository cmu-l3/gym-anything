#!/bin/bash
set -e
echo "=== Exporting Security Audit Task Results ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/security-audit"
PKG_DIR="$PROJECT_DIR/src/main/java/com/auditlib"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Capture Maven Compilation Result
echo "Running compilation check..."
COMPILATION_SUCCESS="false"
COMPILATION_OUTPUT=""

if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    # Capture both stdout and stderr
    OUTPUT=$(su - ga -c "cd $PROJECT_DIR && mvn clean compile" 2>&1)
    COMPILATION_OUTPUT="$OUTPUT"
    
    if echo "$OUTPUT" | grep -q "BUILD SUCCESS"; then
        COMPILATION_SUCCESS="true"
    fi
fi

# 3. Read File Contents for analysis
# Function to read and JSON-escape a file
read_file_content() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        python3 -c "import sys, json; print(json.dumps(open('$fpath').read()))"
    else
        echo "null"
    fi
}

CONTENT_SQL=$(read_file_content "$PKG_DIR/DatabaseHelper.java")
CONTENT_PATH=$(read_file_content "$PKG_DIR/FileManager.java")
CONTENT_RAND=$(read_file_content "$PKG_DIR/TokenGenerator.java")
CONTENT_CREDS=$(read_file_content "$PKG_DIR/ConfigLoader.java")
CONTENT_XXE=$(read_file_content "$PKG_DIR/XmlProcessor.java")
CONTENT_HASH=$(read_file_content "$PKG_DIR/PasswordUtil.java")

# 4. Check modifications (Anti-gaming)
# Generate current checksums
find "$PKG_DIR" -name "*.java" -type f -exec sha256sum {} \; | sort > /tmp/current_checksums.txt

MODIFIED_FILES=$(comm -23 /tmp/initial_checksums.txt /tmp/current_checksums.txt | wc -l)

# 5. Build Result JSON
cat > /tmp/result_data.json << EOF
{
  "compilation_success": $COMPILATION_SUCCESS,
  "modified_file_count": $MODIFIED_FILES,
  "files": {
    "DatabaseHelper.java": $CONTENT_SQL,
    "FileManager.java": $CONTENT_PATH,
    "TokenGenerator.java": $CONTENT_RAND,
    "ConfigLoader.java": $CONTENT_CREDS,
    "XmlProcessor.java": $CONTENT_XXE,
    "PasswordUtil.java": $CONTENT_HASH
  },
  "compilation_output": $(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" <<< "$COMPILATION_OUTPUT"),
  "timestamp": $(date +%s)
}
EOF

# Move to standard location
mv /tmp/result_data.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"