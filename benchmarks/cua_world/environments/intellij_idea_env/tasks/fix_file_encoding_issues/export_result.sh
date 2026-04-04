#!/bin/bash
echo "=== Exporting Fix File Encoding Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/legacy-finance-app"
TARGET_FILE="$PROJECT_DIR/src/main/java/com/legacy/finance/CurrencyConfig.java"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests to see if code compiles and runs correctly
TEST_RESULT="fail"
TEST_OUTPUT=""
if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    # Capture output
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test 2>&1)
    if [ $? -eq 0 ]; then
        TEST_RESULT="pass"
    fi
fi

# 2. Check File Stats
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c%s "$TARGET_FILE")
    
    # Copy the file to a temp location for the verifier to analyze (preserving binary data)
    cp "$TARGET_FILE" /tmp/result_CurrencyConfig.java
    chmod 666 /tmp/result_CurrencyConfig.java
fi

# 3. Check Project Encoding Settings
ENCODING_XML_CONTENT=""
if [ -f "$PROJECT_DIR/.idea/encodings.xml" ]; then
    ENCODING_XML_CONTENT=$(cat "$PROJECT_DIR/.idea/encodings.xml")
fi

# Prepare JSON
# Be careful with JSON escaping for test output
TEST_OUTPUT_ESCAPED=$(echo "$TEST_OUTPUT" | tail -n 50 | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")
ENCODING_XML_ESCAPED=$(echo "$ENCODING_XML_CONTENT" | python3 -c "import json, sys; print(json.dumps(sys.stdin.read()))")

cat > /tmp/task_result.json <<EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "test_result": "$TEST_RESULT",
    "test_output": $TEST_OUTPUT_ESCAPED,
    "project_encoding_xml": $ENCODING_XML_ESCAPED,
    "target_file_path": "/tmp/result_CurrencyConfig.java",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"