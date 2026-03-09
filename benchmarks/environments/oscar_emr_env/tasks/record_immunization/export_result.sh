#!/bin/bash
# Export script for Record Immunization task
set -e

echo "=== Exporting Record Immunization Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PATIENT_ID=$(cat /tmp/task_patient_id.txt 2>/dev/null || echo "")

if [ -z "$PATIENT_ID" ]; then
    # Try to find ID again if temp file missing
    PATIENT_ID=$(get_patient_id "Lucas" "Tremblay")
fi

echo "Checking immunizations for Patient ID: $PATIENT_ID"

# 3. Query Immunizations Table
#    We look for records created or observed today for this patient.
#    Note: Table schema may vary slightly by Oscar version, but standard is 'immunizations'.
#    Columns usually: immunization_name, date_observation, lot, site, route, provider_no

# Helper to get JSON list of immunizations
# We use a query that outputs JSON-like structure or simpler text we can parse.
# Here we'll output raw tab-separated values and parse in Python/verifier, 
# or construct a JSON manually if simple enough.

# Let's dump the relevant rows to a text file.
# Using CONCAT to make it easier to parse or just raw tab output.
SQL_QUERY="SELECT immunization_name, lot, site, route, date_observation 
           FROM immunizations 
           WHERE demographic_no='$PATIENT_ID' 
           ORDER BY id DESC"

# Execute query
# docker exec ... mysql ...
RAW_DATA=$(oscar_query "$SQL_QUERY")

# 4. Check system state (browser running)
BROWSER_RUNNING="false"
if pgrep -f "firefox" > /dev/null; then
    BROWSER_RUNNING="true"
fi

# 5. Create Result JSON
# We will embed the raw SQL output into the JSON string properly escaped
# or just save the raw output to a separate file and read it in verifier.
# To keep it single-file for copy_from_env, we'll try to format it as a JSON list.

# Convert MySQL tab-separated output to JSON array of objects
# Skip header row if present (mysql -N suppresses header)
JSON_RECORDS="["
FIRST=true

while IFS=$'\t' read -r name lot site route date_obs; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        JSON_RECORDS="$JSON_RECORDS,"
    fi
    # Escape quotes
    name=$(echo "$name" | sed 's/"/\\"/g')
    lot=$(echo "$lot" | sed 's/"/\\"/g')
    site=$(echo "$site" | sed 's/"/\\"/g')
    route=$(echo "$route" | sed 's/"/\\"/g')
    
    JSON_RECORDS="$JSON_RECORDS {\"name\": \"$name\", \"lot\": \"$lot\", \"site\": \"$site\", \"route\": \"$route\", \"date\": \"$date_obs\"}"
done <<< "$RAW_DATA"

JSON_RECORDS="$JSON_RECORDS]"

# Write to temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "patient_id": "$PATIENT_ID",
    "browser_was_running": $BROWSER_RUNNING,
    "immunization_records": $JSON_RECORDS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
chmod 666 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json