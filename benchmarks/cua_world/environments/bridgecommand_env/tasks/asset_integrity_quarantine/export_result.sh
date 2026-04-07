#!/bin/bash
echo "=== Exporting Asset Integrity Quarantine Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
QUARANTINE_DIR="/home/ga/Desktop/Quarantined_Assets"
BC_MODELS="/opt/bridgecommand/Models"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Function to list files in a directory as a JSON array
list_files_json() {
    local dir="$1"
    if [ -d "$dir" ]; then
        # Find all files and folders relative to the dir, max depth 1
        find "$dir" -maxdepth 1 -not -path "$dir" -printf '"%f", ' | sed 's/, $//'
    else
        echo ""
    fi
}

# Check if quarantine exists
if [ -d "$QUARANTINE_DIR" ]; then
    QUARANTINE_EXISTS="true"
    QUARANTINE_FILES="[$(list_files_json "$QUARANTINE_DIR")]"
else
    QUARANTINE_EXISTS="false"
    QUARANTINE_FILES="[]"
fi

# List remaining files in source directories
OWNSHIP_FILES="[$(list_files_json "$BC_MODELS/Ownship")]"
OTHER_FILES="[$(list_files_json "$BC_MODELS/Other")]"

# Read report content
REPORT_CONTENT=""
if [ -f "$QUARANTINE_DIR/report.txt" ]; then
    REPORT_CONTENT=$(cat "$QUARANTINE_DIR/report.txt" | tr '\n' ' ' | sed 's/"/\\"/g')
    REPORT_EXISTS="true"
else
    REPORT_EXISTS="false"
fi

# Create result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "quarantine_exists": $QUARANTINE_EXISTS,
    "quarantine_files": $QUARANTINE_FILES,
    "remaining_ownship_files": $OWNSHIP_FILES,
    "remaining_other_files": $OTHER_FILES,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$REPORT_CONTENT"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json