#!/bin/bash
# Export script for Cross-Subdomain Ecosystem Mapping task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Cross-Subdomain Ecosystem Mapping Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_FILE="/home/ga/Documents/SEO/exports/ecosystem_inventory.csv"
REPORT_FILE="/home/ga/Documents/SEO/reports/subdomain_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
SF_RUNNING="false"
CSV_EXISTS="false"
CSV_VALID_TIMESTAMP="false"
CSV_ROW_COUNT=0
HAS_BOOKS_SUBDOMAIN="false"
HAS_QUOTES_SUBDOMAIN="false"
REPORT_EXISTS="false"
REPORT_VALID_TIMESTAMP="false"
REPORT_HAS_COUNTS="false"
WINDOW_INFO=""

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title for VLM/Validation context
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Verify CSV Export
if [ -f "$EXPORT_FILE" ]; then
    CSV_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_VALID_TIMESTAMP="true"
        
        # Analyze CSV content
        # Count rows (excluding header)
        TOTAL_LINES=$(wc -l < "$EXPORT_FILE" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        fi

        # Check for subdomains in the CSV
        if grep -q "books.toscrape.com" "$EXPORT_FILE"; then
            HAS_BOOKS_SUBDOMAIN="true"
        fi
        if grep -q "quotes.toscrape.com" "$EXPORT_FILE"; then
            HAS_QUOTES_SUBDOMAIN="true"
        fi
    fi
fi

# Verify Summary Report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_VALID_TIMESTAMP="true"
        
        # Check if report contains numbers (counts)
        if grep -qE "[0-9]+" "$REPORT_FILE"; then
            REPORT_HAS_COUNTS="true"
        fi
    fi
fi

# Create JSON result
# Using Python to write JSON avoids escaping hell in bash
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_valid_timestamp": $CSV_VALID_TIMESTAMP,
    "csv_row_count": $CSV_ROW_COUNT,
    "has_books_subdomain": $HAS_BOOKS_SUBDOMAIN,
    "has_quotes_subdomain": $HAS_QUOTES_SUBDOMAIN,
    "report_exists": $REPORT_EXISTS,
    "report_valid_timestamp": $REPORT_VALID_TIMESTAMP,
    "report_has_counts": $REPORT_HAS_COUNTS,
    "window_info": """$WINDOW_INFO""",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="