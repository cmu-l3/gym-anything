#!/bin/bash
echo "=== Exporting Graph Algorithms Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/graph-algorithms"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if source file was modified
STUB_HASH=$(cat /tmp/stub_hash.txt | awk '{print $1}')
CURRENT_HASH=$(md5sum "$PROJECT_DIR/src/main/java/graph/GraphAlgorithms.java" 2>/dev/null | awk '{print $1}')
MODIFIED="false"
if [ "$STUB_HASH" != "$CURRENT_HASH" ]; then
    MODIFIED="true"
fi

# 3. Run tests to ensure we have fresh reports
# (Use -Dmaven.test.failure.ignore=true so mvn doesn't exit with error on test failure)
echo "Running tests..."
cd "$PROJECT_DIR"
su - ga -c "JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dmaven.test.failure.ignore=true > /tmp/mvn_test_run.log 2>&1"

# 4. Copy Report Files
mkdir -p /tmp/export/reports
if [ -d "$PROJECT_DIR/target/surefire-reports" ]; then
    cp "$PROJECT_DIR/target/surefire-reports"/*.xml /tmp/export/reports/ 2>/dev/null || true
fi

# 5. Copy Source Code (for static analysis)
if [ -f "$PROJECT_DIR/src/main/java/graph/GraphAlgorithms.java" ]; then
    cp "$PROJECT_DIR/src/main/java/graph/GraphAlgorithms.java" /tmp/export/GraphAlgorithms.java
fi

# 6. Read Source Content safely for JSON
SOURCE_CONTENT=""
if [ -f "/tmp/export/GraphAlgorithms.java" ]; then
    SOURCE_CONTENT=$(cat "/tmp/export/GraphAlgorithms.java")
fi
SOURCE_ESCAPED=$(echo "$SOURCE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 7. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "source_modified": $MODIFIED,
    "source_code": $SOURCE_ESCAPED,
    "timestamp": "$(date -Iseconds)",
    "reports_available": $(ls /tmp/export/reports/*.xml >/dev/null 2>&1 && echo "true" || echo "false")
}
EOF
)

# 8. Save result
write_json_result "$RESULT_JSON" /tmp/task_result.json

# 9. Copy surefire reports to a location accessible by verifier via copy_from_env
# We'll zip them up or just rely on copy_from_env accessing individual files? 
# Verifier can pull /tmp/export/reports contents.
# Let's pack reports into a single JSON field? No, verifier.py can parse XML. 
# We'll verify by reading the XML files in python.

echo "Result saved."
cat /tmp/task_result.json