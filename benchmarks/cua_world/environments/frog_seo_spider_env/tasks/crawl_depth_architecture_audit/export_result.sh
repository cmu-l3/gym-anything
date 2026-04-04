#!/bin/bash
# Export script for Crawl Depth Architecture Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crawl Depth Architecture Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
REPORT_PATH="$REPORTS_DIR/architecture_report.txt"

# Initialize result variables
EXPORT_CSV_PATH=""
EXPORT_CSV_CREATED="false"
REPORT_CREATED="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider\|books.toscrape\|toscrape" | head -1 || echo "")

# 1. FIND THE CSV EXPORT
# We look for the newest CSV in the export directory created AFTER task start
if [ -d "$EXPORT_DIR" ]; then
    # Find all CSVs modified after start time
    NEWEST_CSV=$(find "$EXPORT_DIR" -name "*.csv" -newermt "@$TASK_START_EPOCH" -type f -printf "%T@ %p\n" | sort -n | tail -1 | cut -d' ' -f2-)
    
    if [ -n "$NEWEST_CSV" ]; then
        EXPORT_CSV_PATH="$NEWEST_CSV"
        EXPORT_CSV_CREATED="true"
        echo "Found new export file: $NEWEST_CSV"
        
        # Make a copy for verification to avoid permission issues
        cp "$NEWEST_CSV" /tmp/agent_export.csv
        chmod 644 /tmp/agent_export.csv
    fi
fi

# 2. CHECK REPORT
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START_EPOCH" ]; then
        REPORT_CREATED="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        echo "Found report file: $REPORT_PATH ($REPORT_SIZE bytes)"
        
        # Make a copy for verification
        cp "$REPORT_PATH" /tmp/agent_report.txt
        chmod 644 /tmp/agent_report.txt
    fi
fi

# Write result JSON using Python for safety
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "export_csv_created": "$EXPORT_CSV_CREATED" == "true",
    "export_csv_path": "$EXPORT_CSV_PATH",
    "report_created": "$REPORT_CREATED" == "true",
    "report_path": "$REPORT_PATH",
    "report_size_bytes": $REPORT_SIZE,
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/crawl_depth_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/crawl_depth_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="