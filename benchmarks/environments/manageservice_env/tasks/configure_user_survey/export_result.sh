#!/bin/bash
# Export script for "configure_user_survey" task
# Exports DB state regarding surveys to JSON for verification

echo "=== Exporting User Survey Configuration ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# Extract Survey Data from Database
# ==============================================================================
# Since SDP table names can vary between versions (e.g., SurveyConfig vs ArcSurveyConfig),
# we search relevant tables or dump data containing our target strings.

echo "Dumping survey-related data..."

# 1. Search for the Questions
# We look for the specific question text in the entire database dump of survey tables
# This is robust against schema changes.
SURVEY_DUMP_FILE="/tmp/final_survey_db_dump.txt"

# Get list of survey tables
SURVEY_TABLES=$(sdp_db_exec "SELECT tablename FROM pg_tables WHERE tablename LIKE '%survey%'")

# Dump content of these tables
rm -f "$SURVEY_DUMP_FILE"
for table in $SURVEY_TABLES; do
    # Skip huge tables if any (unlikely for survey config)
    echo "--- TABLE: $table ---" >> "$SURVEY_DUMP_FILE"
    sdp_db_exec "SELECT * FROM $table" >> "$SURVEY_DUMP_FILE" 2>/dev/null || true
done

# 2. Check for Specific Questions (grep from dump)
HAS_Q1="false"
if grep -iq "technical knowledge of the staff" "$SURVEY_DUMP_FILE"; then
    HAS_Q1="true"
fi

HAS_Q2="false"
if grep -iq "resolved in a timely manner" "$SURVEY_DUMP_FILE"; then
    HAS_Q2="true"
fi

# 3. Check for Enabled Status
# Usually in a table like SurveyConfiguration or similar. 
# We look for "true" or "enabled" near "Survey" patterns, or just check the dump for standard flags.
# Often the column is 'status' or 'enable'.
# We'll rely on the verifier to parse the dump more intelligently if needed, 
# but here we'll do a basic check for the 'closed' status trigger if stored as text.

# Just export the full dump content to JSON for Python to analyze
# We encode the dump to base64 to avoid JSON syntax errors
DUMP_B64=$(base64 -w 0 "$SURVEY_DUMP_FILE")

# Check if application (SDP) is running
APP_RUNNING="false"
if pgrep -f "WrapperJVMMain" >/dev/null || pgrep -f "wrapper.java" >/dev/null; then
    APP_RUNNING="true"
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "has_question_technical": $HAS_Q1,
    "has_question_timely": $HAS_Q2,
    "db_dump_base64": "$DUMP_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="