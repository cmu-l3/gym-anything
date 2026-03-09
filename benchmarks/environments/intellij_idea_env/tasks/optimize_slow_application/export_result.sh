#!/bin/bash
echo "=== Exporting optimize_slow_application result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/text-analyzer"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Run Tests to ensure functionality remains correct
echo "Running unit tests..."
TEST_OUTPUT=""
TESTS_PASSED="false"

if [ -f "$PROJECT_DIR/pom.xml" ]; then
    cd "$PROJECT_DIR"
    TEST_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -B 2>&1)
    if [ $? -eq 0 ]; then
        TESTS_PASSED="true"
    fi
else
    TEST_OUTPUT="pom.xml not found"
fi

# 2. Read Source Files for Code Analysis
read_file() {
    local f="$1"
    if [ -f "$f" ]; then
        cat "$f"
    else
        echo ""
    fi
}

SRC_DIR="$PROJECT_DIR/src/main/java/com/textanalyzer"

FILE_WORDCOUNTER=$(read_file "$SRC_DIR/WordCounter.java")
FILE_REPORTGEN=$(read_file "$SRC_DIR/ReportGenerator.java")
FILE_DUPLICATE=$(read_file "$SRC_DIR/DuplicateDetector.java")
FILE_READER=$(read_file "$SRC_DIR/TextFileReader.java")
FILE_TOPWORDS=$(read_file "$SRC_DIR/TopWordsFinder.java")

# 3. Check for results file
RESULTS_FILE_CONTENT=""
RESULTS_FILE_EXISTS="false"
if [ -f "$PROJECT_DIR/optimization_results.txt" ]; then
    RESULTS_FILE_EXISTS="true"
    RESULTS_FILE_CONTENT=$(cat "$PROJECT_DIR/optimization_results.txt")
fi

# Escape for JSON
escape_json() {
    echo "$1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))"
}

JSON_WORDCOUNTER=$(escape_json "$FILE_WORDCOUNTER")
JSON_REPORTGEN=$(escape_json "$FILE_REPORTGEN")
JSON_DUPLICATE=$(escape_json "$FILE_DUPLICATE")
JSON_READER=$(escape_json "$FILE_READER")
JSON_TOPWORDS=$(escape_json "$FILE_TOPWORDS")
JSON_TEST_OUTPUT=$(escape_json "$TEST_OUTPUT")
JSON_RESULTS_TXT=$(escape_json "$RESULTS_FILE_CONTENT")

# Create JSON
cat > /tmp/result.json << EOF
{
    "tests_passed": $TESTS_PASSED,
    "results_file_exists": $RESULTS_FILE_EXISTS,
    "test_output": $JSON_TEST_OUTPUT,
    "source_files": {
        "WordCounter.java": $JSON_WORDCOUNTER,
        "ReportGenerator.java": $JSON_REPORTGEN,
        "DuplicateDetector.java": $JSON_DUPLICATE,
        "TextFileReader.java": $JSON_READER,
        "TopWordsFinder.java": $JSON_TOPWORDS
    },
    "results_txt_content": $JSON_RESULTS_TXT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Secure copy
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="