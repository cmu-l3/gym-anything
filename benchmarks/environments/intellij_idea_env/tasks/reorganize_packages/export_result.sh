#!/bin/bash
echo "=== Exporting reorganize_packages result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-system"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Attempt Compilation
echo "Compiling project..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile 2>&1)
BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    BUILD_SUCCESS="true"
else
    BUILD_SUCCESS="false"
fi

# 2. Map File Structure
# Find where files actually ended up
STRUCTURE=$(find src/main/java -name "*.java")

# 3. Capture content of key files for verification (only needed if copy_from_env fails, but we use it primarily)
# We will rely on verifier.py pulling specific files, but let's record the mapping here.

# Create Result JSON
# We escape the build output to ensure valid JSON
BUILD_OUTPUT_ESCAPED=$(echo "$BUILD_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
STRUCTURE_ESCAPED=$(echo "$STRUCTURE" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

RESULT_JSON=$(cat << EOF
{
    "build_success": $BUILD_SUCCESS,
    "build_output": $BUILD_OUTPUT_ESCAPED,
    "file_structure": $STRUCTURE_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="