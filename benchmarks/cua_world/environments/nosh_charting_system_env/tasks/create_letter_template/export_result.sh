#!/bin/bash
# Export script for create_letter_template task
# Verifies the template creation by querying the database

echo "=== Exporting create_letter_template result ==="

# Source timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)

# Capture final screenshot for VLM verification
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# --- Database Verification ---
# We search for the unique content string in the database. 
# Since schemas can vary, we search in the most likely tables for templates.

TARGET_STRING="We are honored that you have chosen us"
TARGET_TITLE="New Patient Welcome"

# Helper function to run SQL
run_sql() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1" 2>/dev/null
}

echo "Searching database for template..."

# Check table 1: form_layout (Common for templates in NOSH/OpenEMR forks)
# Looking for records created/modified recently if timestamps exist, or just existence
MATCH_1=$(run_sql "SELECT form_id, form_name, form_layout FROM form_layout WHERE form_name='$TARGET_TITLE' OR form_layout LIKE '%$TARGET_STRING%' LIMIT 1")

# Check table 2: documents_templates (Alternative schema location)
MATCH_2=$(run_sql "SELECT id, title, body FROM documents_templates WHERE title='$TARGET_TITLE' OR body LIKE '%$TARGET_STRING%' LIMIT 1")

# Analyze results
FOUND_RECORD="false"
FOUND_TITLE=""
FOUND_CONTENT=""
TABLE_SOURCE=""

if [ -n "$MATCH_1" ]; then
    FOUND_RECORD="true"
    TABLE_SOURCE="form_layout"
    # Basic parsing (tabs separated usually)
    FOUND_TITLE=$(echo "$MATCH_1" | awk -F'\t' '{print $2}')
    FOUND_CONTENT=$(echo "$MATCH_1" | awk -F'\t' '{print $3}')
elif [ -n "$MATCH_2" ]; then
    FOUND_RECORD="true"
    TABLE_SOURCE="documents_templates"
    FOUND_TITLE=$(echo "$MATCH_2" | awk -F'\t' '{print $2}')
    FOUND_CONTENT=$(echo "$MATCH_2" | awk -F'\t' '{print $3}')
fi

# Escape content for JSON safety
SAFE_TITLE=$(echo "$FOUND_TITLE" | sed 's/"/\\"/g' | tr -d '\n')
SAFE_CONTENT=$(echo "$FOUND_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')

# Check App State
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "export_time": $EXPORT_TIME,
    "found_record": $FOUND_RECORD,
    "table_source": "$TABLE_SOURCE",
    "found_title": "$SAFE_TITLE",
    "found_content_sample": "${SAFE_CONTENT:0:100}", 
    "full_content_match": $(echo "$SAFE_CONTENT" | grep -q "$TARGET_STRING" && echo "true" || echo "false"),
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to final location with broad permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="