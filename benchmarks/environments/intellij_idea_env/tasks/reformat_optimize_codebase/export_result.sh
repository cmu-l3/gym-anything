#!/bin/bash
set -e
echo "=== Exporting reformat_optimize_codebase result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/IdeaProjects/inventory-manager"
SRC_DIR="$PROJECT_DIR/src/main/java/com/inventory"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Capture file contents of the 5 Java files
FILES=("Product.java" "Warehouse.java" "InventoryService.java" "Category.java" "InventoryApp.java")
FILE_CONTENTS_JSON=""

for file in "${FILES[@]}"; do
    FILE_PATH="$SRC_DIR/$file"
    if [ -f "$FILE_PATH" ]; then
        # Check modification time
        MTIME=$(stat -c %Y "$FILE_PATH" 2>/dev/null || echo "0")
        WAS_MODIFIED="false"
        if [ "$MTIME" -gt "$TASK_START" ]; then
            WAS_MODIFIED="true"
        fi
        
        # Read content and escape for JSON
        CONTENT=$(cat "$FILE_PATH" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
        
        # Add comma if not first
        if [ -n "$FILE_CONTENTS_JSON" ]; then
            FILE_CONTENTS_JSON="$FILE_CONTENTS_JSON,"
        fi
        
        FILE_CONTENTS_JSON="$FILE_CONTENTS_JSON \"$file\": {\"content\": $CONTENT, \"modified\": $WAS_MODIFIED}"
    fi
done

# Check compilation status
cd "$PROJECT_DIR"
COMPILE_STATUS="unknown"
COMPILE_OUTPUT=""
if [ -f "pom.xml" ]; then
    COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q 2>&1 | tail -n 20)
    if [ $? -eq 0 ]; then
        COMPILE_STATUS="success"
    else
        COMPILE_STATUS="failure"
    fi
fi

# Escape compile output
COMPILE_OUTPUT_ESC=$(echo "$COMPILE_OUTPUT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "files": {
        $FILE_CONTENTS_JSON
    },
    "compilation": {
        "status": "$COMPILE_STATUS",
        "output": $COMPILE_OUTPUT_ESC
    },
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="