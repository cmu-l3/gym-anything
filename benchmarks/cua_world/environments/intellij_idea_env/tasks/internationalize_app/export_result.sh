#!/bin/bash
echo "=== Exporting Internationalization Result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/library-manager"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- 1. Check Compilation ---
echo "Checking compilation..."
cd "$PROJECT_DIR"
COMPILE_OUTPUT=$(JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn clean compile 2>&1)
COMPILE_EXIT_CODE=$?

if [ $COMPILE_EXIT_CODE -eq 0 ]; then
    echo "Compilation successful."
    COMPILES="true"
else
    echo "Compilation failed."
    COMPILES="false"
fi

# --- 2. Collect Java Source Files ---
# We want to check if they still contain hardcoded strings and if they use ResourceBundle
JAVA_SOURCES="{}"
for java_file in "$PROJECT_DIR"/src/main/java/com/library/*.java; do
    if [ -f "$java_file" ]; then
        fname=$(basename "$java_file")
        content=$(cat "$java_file" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
        mtime=$(stat -c %Y "$java_file")
        JAVA_SOURCES=$(echo "$JAVA_SOURCES" | python3 -c "import sys, json; data=json.load(sys.stdin); data['$fname']={'content': $content, 'mtime': $mtime}; print(json.dumps(data))")
    fi
done

# --- 3. Collect Properties Files ---
PROPERTIES_FILES="{}"
# Look for standard properties files
for prop_file in "$PROJECT_DIR"/src/main/resources/*.properties; do
    if [ -f "$prop_file" ]; then
        fname=$(basename "$prop_file")
        content=$(cat "$prop_file" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))")
        mtime=$(stat -c %Y "$prop_file")
        PROPERTIES_FILES=$(echo "$PROPERTIES_FILES" | python3 -c "import sys, json; data=json.load(sys.stdin); data['$fname']={'content': $content, 'mtime': $mtime}; print(json.dumps(data))")
    fi
done

# --- 4. Construct JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "compilation_success": $COMPILES,
    "compilation_output": $(echo "$COMPILE_OUTPUT" | tail -n 20 | python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))"),
    "java_files": $JAVA_SOURCES,
    "properties_files": $PROPERTIES_FILES,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with correct permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="