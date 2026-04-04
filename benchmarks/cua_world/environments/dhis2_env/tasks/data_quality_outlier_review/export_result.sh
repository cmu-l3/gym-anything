#!/bin/bash
# Export script for Data Quality Outlier Review task

echo "=== Exporting Data Quality Outlier Review Result ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type dhis2_query &>/dev/null; then
    dhis2_query() {
        local query="$1"
        docker exec dhis2-db psql -U dhis -d dhis2 -t -c "$query" 2>/dev/null
    }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load start time
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_FOLLOWUP_COUNT=$(cat /tmp/initial_followup_count 2>/dev/null || echo "0")

echo "Task start: $TASK_START"
echo "Initial follow-ups: $INITIAL_FOLLOWUP_COUNT"

# 1. Check Database for NEW follow-up flags
# We count total follow-ups now
CURRENT_FOLLOWUP_COUNT=$(dhis2_query "SELECT COUNT(*) FROM datavalue WHERE followup = true" | tr -d ' ' || echo "0")
# We also try to count ones specifically updated recently (more robust)
# Note: lastupdated is usually a timestamp. We check for updates since task start.
NEWLY_UPDATED_FOLLOWUPS=$(dhis2_query "SELECT COUNT(*) FROM datavalue WHERE followup = true AND lastupdated >= to_timestamp($TASK_START)" | tr -d ' ' || echo "0")

echo "Current follow-ups: $CURRENT_FOLLOWUP_COUNT"
echo "Newly updated follow-ups: $NEWLY_UPDATED_FOLLOWUPS"

# 2. Check for Exported File in Downloads
DOWNLOADS_DIR="/home/ga/Downloads"
EXPORT_FILE_FOUND="false"
EXPORT_FILENAME=""
if [ -d "$DOWNLOADS_DIR" ]; then
    # Find files modified after task start
    # Look for likely export formats: csv, xls, xlsx, json, pdf
    RECENT_FILE=$(find "$DOWNLOADS_DIR" -type f \( -name "*.csv" -o -name "*.xls" -o -name "*.xlsx" -o -name "*.json" -o -name "*.pdf" \) -newermt "@$TASK_START" -print -quit)
    if [ -n "$RECENT_FILE" ]; then
        EXPORT_FILE_FOUND="true"
        EXPORT_FILENAME=$(basename "$RECENT_FILE")
    fi
fi
echo "Export file found: $EXPORT_FILE_FOUND ($EXPORT_FILENAME)"

# 3. Check for Summary Report
REPORT_PATH="/home/ga/Desktop/kailahun_data_quality_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_LENGTH=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_LENGTH=$(stat -c %s "$REPORT_PATH")
    # Read content (safely, first 1000 chars)
    REPORT_CONTENT=$(head -c 1000 "$REPORT_PATH" | tr '\n' ' ' | sed 's/"/\\"/g')
fi
echo "Report exists: $REPORT_EXISTS (Length: $REPORT_LENGTH)"

# Create JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_followup_count": $INITIAL_FOLLOWUP_COUNT,
    "current_followup_count": $CURRENT_FOLLOWUP_COUNT,
    "newly_updated_followups": $NEWLY_UPDATED_FOLLOWUPS,
    "export_file_found": $EXPORT_FILE_FOUND,
    "export_filename": "$EXPORT_FILENAME",
    "report_exists": $REPORT_EXISTS,
    "report_length": $REPORT_LENGTH,
    "report_content_preview": "$REPORT_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="