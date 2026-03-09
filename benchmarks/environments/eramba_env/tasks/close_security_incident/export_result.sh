#!/bin/bash
echo "=== Exporting close_security_incident results ==="

# 1. Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 3. Query Database for the Incident State
# We fetch all relevant text fields to check where the agent put the info
echo "Querying database for incident details..."
# We use a comprehensive query. If columns don't exist, this might error, so we construct it carefully or fallback.
# Eramba schema often varies, but we check common fields.
# We will dump the whole row as JSON if possible, or select specific columns.

QUERY="SELECT title, status, description, analysis, remediation, closure_notes, modified FROM security_incidents WHERE title='Unauthorized VPN Access from External IP'"

# Try to run query. If specific columns (analysis/remediation) don't exist, we fall back to a simpler one.
# But for the task to be valid, we assume the environment supports these standard incident fields.
RAW_RESULT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -E -e "$QUERY" 2>/dev/null || \
             docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -E -e "SELECT title, status, description, modified FROM security_incidents WHERE title='Unauthorized VPN Access from External IP'" 2>/dev/null)

# Save raw output for debugging
echo "$RAW_RESULT" > /tmp/db_raw_output.txt

# Parse the MySQL vertical output (-E) into a simple JSON structure
# This is a hacky but effective way to get DB rows into JSON without external tools inside the container
# Format is: 
# *************************** 1. row ***************************
#       title: Unauthorized VPN Access...
#      status: 2
# ...
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "{" > "$TEMP_JSON"
echo "  \"task_start\": $TASK_START," >> "$TEMP_JSON"
echo "  \"task_end\": $TASK_END," >> "$TEMP_JSON"
echo "  \"incident_found\": true," >> "$TEMP_JSON"
echo "  \"db_data\": {" >> "$TEMP_JSON"

# Extract fields
TITLE=$(grep "title:" /tmp/db_raw_output.txt | sed 's/title: //' | tr -d '\n' | sed 's/"/\\"/g')
STATUS=$(grep "status:" /tmp/db_raw_output.txt | sed 's/status: //' | tr -d '\n')
MODIFIED=$(grep "modified:" /tmp/db_raw_output.txt | sed 's/modified: //' | tr -d '\n')
# Capture all text content for keyword searching
ALL_TEXT=$(cat /tmp/db_raw_output.txt | grep -v "\*\*" | grep -v "status:" | grep -v "modified:" | tr '\n' ' ' | sed 's/"/\\"/g')

echo "    \"title\": \"$TITLE\"," >> "$TEMP_JSON"
echo "    \"status\": \"$STATUS\"," >> "$TEMP_JSON"
echo "    \"modified\": \"$MODIFIED\"," >> "$TEMP_JSON"
echo "    \"full_text\": \"$ALL_TEXT\"" >> "$TEMP_JSON"
echo "  }" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# 4. Save result to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="