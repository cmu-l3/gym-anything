#!/bin/bash
echo "=== Exporting add_javadoc_documentation result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/tuple-utils"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Check Javadoc HTML generation
HTML_INDEX="$PROJECT_DIR/target/site/apidocs/index.html"
HTML_PACKAGE="$PROJECT_DIR/target/site/apidocs/org/apache/commons/lang3/tuple/package-summary.html"
HTML_GENERATED="false"

if [ -f "$HTML_INDEX" ] && [ -f "$HTML_PACKAGE" ]; then
    HTML_GENERATED="true"
    # Check if generated during task
    HTML_MTIME=$(stat -c %Y "$HTML_INDEX" 2>/dev/null || echo "0")
    if [ "$HTML_MTIME" -lt "$TASK_START" ]; then
        HTML_GENERATED="false_stale"
    fi
fi

# Check Compilation (Run verification compile to ensure code is valid)
# We run this as verification because agent might have broken the code
COMPILE_SUCCESS="false"
cd "$PROJECT_DIR"
if JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>/dev/null; then
    COMPILE_SUCCESS="true"
fi

# Check Doc Report
DOC_REPORT_PATH="$PROJECT_DIR/doc-report.txt"
DOC_REPORT_EXISTS="false"
DOC_REPORT_CONTENT=""
if [ -f "$DOC_REPORT_PATH" ]; then
    DOC_REPORT_EXISTS="true"
    DOC_REPORT_CONTENT=$(cat "$DOC_REPORT_PATH" | head -n 5)
fi

# Create result JSON
# We don't read the source files here into JSON because they are large.
# The verifier will read them directly using copy_from_env.
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "html_generated": "$HTML_GENERATED",
    "compile_success": $COMPILE_SUCCESS,
    "doc_report_exists": $DOC_REPORT_EXISTS,
    "doc_report_content": $(echo "$DOC_REPORT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="