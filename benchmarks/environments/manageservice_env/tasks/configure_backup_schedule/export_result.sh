#!/bin/bash
# Export script for "configure_backup_schedule" task
# Exports relevant database tables to JSON for verification

echo "=== Exporting Backup Schedule Result ==="
source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Function to export a table to JSON-like structure (headers + data)
export_table_to_json() {
    local table_name="$1"
    local output_file="$2"
    
    # Use psql to get data in CSV format with headers, then we'll wrap it in JSON later or parse in python
    # We use '|' as delimiter to avoid comma issues with email lists
    local content
    content=$(sdp_db_exec "COPY (SELECT * FROM $table_name) TO STDOUT WITH CSV HEADER DELIMITER '|';" 2>/dev/null)
    
    if [ -n "$content" ]; then
        echo "$content" > "$output_file"
        echo "true"
    else
        echo "false"
    fi
}

# Export potential tables
# ServiceDesk Plus DB schema varies, so we check a few likely candidates
BACKUP_TABLE_FOUND=$(export_table_to_json "backupschedule" "/tmp/db_backupschedule.csv")
PERIODIC_TABLE_FOUND=$(export_table_to_json "periodic_backup_schedule" "/tmp/db_periodic_backup.csv")

# Also check for scheduled tasks that might look like backups
TASK_INPUT_FOUND=$(export_table_to_json "task_input" "/tmp/db_task_input.csv")
SCHEDULE_FOUND=$(export_table_to_json "schedule" "/tmp/db_schedule.csv")

# Create the result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# We embed the CSV content into the JSON fields for the python verifier to parse
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "tables": {
        "backupschedule": {
            "found": $BACKUP_TABLE_FOUND,
            "path": "/tmp/db_backupschedule.csv"
        },
        "periodic_backup_schedule": {
            "found": $PERIODIC_TABLE_FOUND,
            "path": "/tmp/db_periodic_backup.csv"
        },
        "task_input": {
            "found": $TASK_INPUT_FOUND,
            "path": "/tmp/db_task_input.csv"
        },
        "schedule": {
            "found": $SCHEDULE_FOUND,
            "path": "/tmp/db_schedule.csv"
        }
    }
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="