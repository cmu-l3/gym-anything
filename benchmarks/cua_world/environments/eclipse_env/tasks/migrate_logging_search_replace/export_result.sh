#!/bin/bash
set -e
echo "=== Exporting migrate_logging_search_replace result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
PROJECT_DIR="/home/ga/eclipse-workspace/DataPipeline"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check compilation and execution
cd "$PROJECT_DIR"
COMPILE_SUCCESS="false"
EXEC_SUCCESS="false"

# Run Maven compile
if run_maven "$PROJECT_DIR" "compile" "/tmp/compile_output.log"; then
    COMPILE_SUCCESS="true"
fi

# Run Maven exec (to verify runtime)
if run_maven "$PROJECT_DIR" "exec:java" "/tmp/exec_output.log"; then
    EXEC_SUCCESS="true"
fi

# 3. Analyze Source Code for Migration Status
# We use grep to count occurrences
cd "$PROJECT_DIR/src/main/java"

# Count remaining System.out.println (excluding comments roughly)
REMAINING_OUT=$(grep -r "System.out.println" . | grep -v "//" | wc -l)
REMAINING_ERR=$(grep -r "System.err.println" . | grep -v "//" | wc -l)

# Check specifically if Main.java still has the required line
MAIN_HAS_REQUIRED_LINE="false"
if grep -Fq 'System.out.println("PIPELINE_RESULT=SUCCESS' com/datapipeline/main/Main.java; then
    MAIN_HAS_REQUIRED_LINE="true"
fi

# Count Logger usages
LOGGER_IMPORTS=$(grep -r "import java.util.logging.Logger;" . | wc -l)
LOGGER_FIELDS=$(grep -r "Logger.getLogger" . | wc -l)
LOGGER_CALLS=$(grep -r "LOGGER\.\(info\|warning\|severe\|fine\|config\)" . | wc -l)

# 4. Check for Agent Report
REPORT_PATH="/home/ga/eclipse-workspace/DataPipeline/migration_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 500) # Limit size
fi

# 5. Compile Result JSON
# Handle proper JSON escaping for report content
REPORT_CONTENT_ESCAPED=$(echo "$REPORT_CONTENT" | jq -R .)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "compile_success": $COMPILE_SUCCESS,
  "exec_success": $EXEC_SUCCESS,
  "remaining_system_out": $REMAINING_OUT,
  "remaining_system_err": $REMAINING_ERR,
  "main_has_required_line": $MAIN_HAS_REQUIRED_LINE,
  "logger_imports": $LOGGER_IMPORTS,
  "logger_fields": $LOGGER_FIELDS,
  "logger_calls": $LOGGER_CALLS,
  "report_exists": $REPORT_EXISTS,
  "report_content": $REPORT_CONTENT_ESCAPED
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="