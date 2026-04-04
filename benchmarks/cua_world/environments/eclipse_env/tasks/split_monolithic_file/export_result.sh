#!/bin/bash
echo "=== Exporting split_monolithic_file result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/CommandPatternApp"
PKG_DIR="$PROJECT_DIR/src/com/example/commands"

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check file existence
echo "Checking file existence..."
FILES_EXIST_COUNT=0
ALL_FILES_EXIST="true"
EXPECTED_FILES=("Command.java" "UndoableCommand.java" "TextDocument.java" "InsertTextCommand.java" "DeleteTextCommand.java" "MacroCommand.java" "CommandInvoker.java")

FILES_STATUS="{}"

for file in "${EXPECTED_FILES[@]}"; do
    if [ -f "$PKG_DIR/$file" ]; then
        FILES_EXIST_COUNT=$((FILES_EXIST_COUNT + 1))
        # Simple JSON append (using python to avoid complexity)
        FILES_STATUS=$(echo "$FILES_STATUS" | python3 -c "import sys, json; data=json.load(sys.stdin); data['$file'] = True; print(json.dumps(data))")
    else
        ALL_FILES_EXIST="false"
        FILES_STATUS=$(echo "$FILES_STATUS" | python3 -c "import sys, json; data=json.load(sys.stdin); data['$file'] = False; print(json.dumps(data))")
    fi
done

# 2. Check monolithic file status
MONOLITHIC_STATUS="unknown"
if [ ! -f "$PKG_DIR/CommandSystem.java" ]; then
    MONOLITHIC_STATUS="deleted"
else
    # Count classes/interfaces in the file
    TYPE_COUNT=$(grep -E "^\s*(public\s+)?(class|interface|enum)\s+\w+" "$PKG_DIR/CommandSystem.java" | wc -l)
    MONOLITHIC_STATUS="exists_with_${TYPE_COUNT}_types"
fi

# 3. Check compilation (System verification)
echo "Verifying compilation..."
COMPILE_SUCCESS="false"
COMPILE_LOG="/tmp/verification_compile.log"

# Clean bin first to be sure
rm -rf "$PROJECT_DIR/bin/*"

if cd "$PROJECT_DIR" && JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 javac -d bin -sourcepath src "$PKG_DIR/Main.java" > "$COMPILE_LOG" 2>&1; then
    COMPILE_SUCCESS="true"
    echo "Compilation successful"
else
    echo "Compilation failed:"
    cat "$COMPILE_LOG"
fi

# 4. Check runtime output (System verification)
echo "Verifying runtime behavior..."
RUNTIME_MATCH="false"
RUNTIME_OUTPUT=""
EXPECTED_OUTPUT=$(cat /tmp/expected_output.txt)

if [ "$COMPILE_SUCCESS" = "true" ]; then
    JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64 java -cp bin com.example.commands.Main > /tmp/system_run_output.txt 2>&1
    RUNTIME_OUTPUT=$(cat /tmp/system_run_output.txt)
    
    # Compare ignoring whitespace
    if diff -wB /tmp/expected_output.txt /tmp/system_run_output.txt > /dev/null; then
        RUNTIME_MATCH="true"
    fi
fi

# 5. Check Agent's reported output file
AGENT_OUTPUT_EXISTS="false"
AGENT_OUTPUT_MATCH="false"
if [ -f "/home/ga/refactored_output.txt" ]; then
    AGENT_OUTPUT_EXISTS="true"
    if diff -wB /tmp/expected_output.txt /home/ga/refactored_output.txt > /dev/null; then
        AGENT_OUTPUT_MATCH="true"
    fi
fi

# Prepare JSON result
RESULT_JSON=$(cat << EOF
{
    "files_exist_count": $FILES_EXIST_COUNT,
    "files_status": $FILES_STATUS,
    "monolithic_status": "$MONOLITHIC_STATUS",
    "compile_success": $COMPILE_SUCCESS,
    "runtime_match": $RUNTIME_MATCH,
    "agent_output_exists": $AGENT_OUTPUT_EXISTS,
    "agent_output_match": $AGENT_OUTPUT_MATCH,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_json_result "$RESULT_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="