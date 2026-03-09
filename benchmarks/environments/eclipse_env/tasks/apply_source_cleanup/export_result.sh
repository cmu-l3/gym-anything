#!/bin/bash
echo "=== Exporting apply_source_cleanup result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/InventoryManager"
SRC_DIR="$PROJECT_DIR/src"

# 1. Take final screenshot
take_screenshot /tmp/task_end.png

# 2. Check compilation status (Headless check using javac)
# We use javac with -Xlint:all to catch warnings
echo "Compiling project to check for errors and warnings..."
mkdir -p /tmp/bin_check

# Find all java files
find "$SRC_DIR" -name "*.java" > /tmp/sources.txt

# Compile
# capture stderr to file
javac -d /tmp/bin_check -Xlint:all @/tmp/sources.txt 2> /tmp/compile_output.txt
COMPILE_EXIT_CODE=$?

# Count errors and warnings
ERROR_COUNT=0
WARNING_COUNT=0
if [ $COMPILE_EXIT_CODE -ne 0 ]; then
    ERROR_COUNT=$(grep -c "error:" /tmp/compile_output.txt || echo "1")
fi
WARNING_COUNT=$(grep -c "warning:" /tmp/compile_output.txt || echo "0")

echo "Compilation exit code: $COMPILE_EXIT_CODE"
echo "Errors: $ERROR_COUNT"
echo "Warnings: $WARNING_COUNT"

# 3. Export file contents for verification
# We copy the specific source files we want to check
mkdir -p /tmp/export_src
cp "$SRC_DIR/com/warehouse/model/Product.java" /tmp/export_src/ 2>/dev/null || true
cp "$SRC_DIR/com/warehouse/model/Category.java" /tmp/export_src/ 2>/dev/null || true
cp "$SRC_DIR/com/warehouse/service/InventoryService.java" /tmp/export_src/ 2>/dev/null || true

# 4. Create result JSON
RESULT_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$RESULT_JSON" << EOF
{
    "compile_exit_code": $COMPILE_EXIT_CODE,
    "error_count": $ERROR_COUNT,
    "warning_count": $WARNING_COUNT,
    "compile_output": $(jq -Rs . < /tmp/compile_output.txt),
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
write_json_result "$(cat $RESULT_JSON)" /tmp/task_result.json
rm -f "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="