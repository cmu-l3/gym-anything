#!/bin/bash
echo "=== Exporting implement_interfaces_generate result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/music-catalog"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Run tests to generate fresh reports for verifier
echo "Running tests for verification..."
cd "$PROJECT_DIR"
# Force run even if agent already ran it, to ensure we have trusted results
JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn test -Dmaven.test.failure.ignore=true > /tmp/final_mvn_output.log 2>&1
MVN_EXIT=$?

# Gather file statistics
FILES_MODIFIED_COUNT=0
for f in "$PROJECT_DIR/src/main/java/com/musiccatalog/impl"/*.java; do
    if [ -f "$f" ]; then
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -gt "$TASK_START" ]; then
            FILES_MODIFIED_COUNT=$((FILES_MODIFIED_COUNT + 1))
        fi
    fi
done

# Create a simplified JSON result
# The Python verifier will do the heavy lifting of parsing XML/Java files
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "mvn_exit_code": $MVN_EXIT,
    "files_modified_count": $FILES_MODIFIED_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="