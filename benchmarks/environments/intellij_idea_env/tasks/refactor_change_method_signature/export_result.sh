#!/bin/bash
echo "=== Exporting Refactoring Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/warehouse-system"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Attempt Compilation (Verify code validity)
echo "Running maven compile..."
cd "$PROJECT_DIR"
BUILD_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile 2>&1)
BUILD_EXIT_CODE=$?

# 3. Read Source Files
SERVICE_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/service/InventoryService.java" 2>/dev/null)
CALLER_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/logistics/client/OrderProcessor.java" 2>/dev/null)

# 4. Check if files were modified
INITIAL_SUM=$(cat /tmp/initial_checksums.txt 2>/dev/null | awk '{print $1}')
CURRENT_SUM=$(md5sum "$PROJECT_DIR/src/main/java/com/logistics/service/InventoryService.java" 2>/dev/null | awk '{print $1}')
FILE_MODIFIED="false"
if [ "$INITIAL_SUM" != "$CURRENT_SUM" ]; then
    FILE_MODIFIED="true"
fi

# 5. Prepare JSON Result
# Escape contents for JSON safety
ESC_SERVICE=$(echo "$SERVICE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
ESC_CALLER=$(echo "$CALLER_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
ESC_BUILD_OUT=$(echo "$BUILD_OUTPUT" | tail -n 20 | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

cat > /tmp/task_result.json << EOF
{
  "build_exit_code": $BUILD_EXIT_CODE,
  "build_output_snippet": $ESC_BUILD_OUT,
  "file_modified": $FILE_MODIFIED,
  "service_content": $ESC_SERVICE,
  "caller_content": $ESC_CALLER,
  "timestamp": "$(date +%s)"
}
EOF

# Secure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Build exit code: $BUILD_EXIT_CODE"