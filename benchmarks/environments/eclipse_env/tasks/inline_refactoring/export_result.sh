#!/bin/bash
echo "=== Exporting inline_refactoring result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/DataProcessor"
RESULT_FILE="/tmp/task_result.json"
REPORT_FILE="$PROJECT_DIR/refactoring_report.txt"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check source files for presence of methods (should be GONE)
# We use grep. If grep finds the method definition, the task failed for that method.
# We search for the *definition*, e.g., "public static String trimInput"

check_method_missing() {
    local file="$1"
    local pattern="$2"
    if [ -f "$file" ]; then
        if grep -q "$pattern" "$file"; then
            echo "false"
        else
            echo "true"
        fi
    else
        echo "file_missing"
    fi
}

TRIM_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/StringProcessor.java" "public static String trimInput")
EMPTY_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/StringProcessor.java" "public static boolean checkEmpty")
ADD_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/MathHelper.java" "public static int addValues")
ABS_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/MathHelper.java" "public static int computeAbsolute")
VAL_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/DataPipeline.java" "private boolean invokeValidation")
WRAP_GONE=$(check_method_missing "$PROJECT_DIR/src/main/java/com/dataproc/core/DataPipeline.java" "private String wrapResult")

# 3. Verify project compiles and tests pass
# We run maven inside the container to get authoritative build status
echo "Running Maven verification..."
COMPILE_STATUS="false"
TEST_STATUS="false"

if [ -d "$PROJECT_DIR" ]; then
    # Run compile
    if su - ga -c "cd $PROJECT_DIR && mvn compile -q"; then
        COMPILE_STATUS="true"
    fi
    
    # Run tests (only if compile succeeded)
    if [ "$COMPILE_STATUS" = "true" ]; then
        if su - ga -c "cd $PROJECT_DIR && mvn test -q"; then
            TEST_STATUS="true"
        fi
    fi
fi

# 4. Check report file
REPORT_EXISTS="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Basic check if it contains reasonable text
    REPORT_CONTENT=$(cat "$REPORT_FILE")
fi

# 5. Read file contents for VLM or detail verification
PIPELINE_CONTENT=""
if [ -f "$PROJECT_DIR/src/main/java/com/dataproc/core/DataPipeline.java" ]; then
    PIPELINE_CONTENT=$(cat "$PROJECT_DIR/src/main/java/com/dataproc/core/DataPipeline.java")
fi

# Escaping for JSON
PIPELINE_ESCAPED=$(echo "$PIPELINE_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# 6. Create JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "trim_gone": "$TRIM_GONE",
    "empty_gone": "$EMPTY_GONE",
    "add_gone": "$ADD_GONE",
    "abs_gone": "$ABS_GONE",
    "val_gone": "$VAL_GONE",
    "wrap_gone": "$WRAP_GONE",
    "compile_success": $COMPILE_STATUS,
    "test_success": $TEST_STATUS,
    "report_exists": $REPORT_EXISTS,
    "pipeline_content": $PIPELINE_ESCAPED,
    "timestamp": "$(date -Iseconds)"
}
EOF

write_json_result "$TEMP_JSON" "$RESULT_FILE"
rm -f "$TEMP_JSON"

echo "Result exported to $RESULT_FILE"
echo "=== Export complete ==="