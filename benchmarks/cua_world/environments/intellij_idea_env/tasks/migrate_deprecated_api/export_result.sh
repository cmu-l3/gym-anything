#!/bin/bash
echo "=== Exporting migrate_deprecated_api result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/data-pipeline"

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_end.png

# Run Maven compile to verify the code actually works
echo "Running Maven compile verification..."
COMPILE_EXIT_CODE=1
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    # Capture output for potential debugging
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 mvn compile -q > /tmp/maven_compile_output.log 2>&1
    COMPILE_EXIT_CODE=$?
fi

# Capture file modification times
find "$PROJECT_DIR/src" -name "*.java" -exec stat -c "%n %Y" {} \; > /tmp/final_file_stats.txt

# Create result JSON
# We don't read file content here; we let the verifier do that via copy_from_env
# We only provide the runtime checks (compilation) and timestamps
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "compile_exit_code": $COMPILE_EXIT_CODE,
    "screenshot_path": "/tmp/task_end.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="