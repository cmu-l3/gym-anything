#!/bin/bash
# Export script for XPath Meta Extraction Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting XPath Meta Extraction Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV_NAME="meta_extraction.csv"
EXPECTED_REPORT_NAME="meta_completeness_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to store verification data
CSV_EXISTS="false"
CSV_PATH=""
CSV_ROW_COUNT=0
CSV_COLUMNS=""
CSV_HAS_TARGET_DOMAIN="false"
CSV_HAS_EXTRACTION_DATA="false"
CSV_HAS_VIEWPORT_DATA="false"

REPORT_EXISTS="false"
REPORT_PATH=""
REPORT_SIZE=0
REPORT_CONTENT=""

SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- 1. Find and Analyze CSV ---

# Priority 1: Check exact expected filename
if [ -f "$EXPORT_DIR/$EXPECTED_CSV_NAME" ]; then
    FILE_EPOCH=$(stat -c %Y "$EXPORT_DIR/$EXPECTED_CSV_NAME" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_EXISTS="true"
        CSV_PATH="$EXPORT_DIR/$EXPECTED_CSV_NAME"
    fi
fi

# Priority 2: Look for any valid CSV if specific name not found
if [ "$CSV_EXISTS" = "false" ]; then
    # Find most recently modified CSV in export dir
    LATEST_CSV=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
    if [ -n "$LATEST_CSV" ]; then
        FILE_EPOCH=$(stat -c %Y "$LATEST_CSV" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            CSV_EXISTS="true"
            CSV_PATH="$LATEST_CSV"
        fi
    fi
fi

if [ "$CSV_EXISTS" = "true" ]; then
    # Count rows (minus header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi
    
    # Read header
    HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    CSV_COLUMNS="$HEADER"
    
    # Check for target domain
    if grep -qi "books.toscrape.com" "$CSV_PATH" 2>/dev/null; then
        CSV_HAS_TARGET_DOMAIN="true"
    fi
    
    # Check for extraction data columns/values
    # Note: Column names might be "Extraction 1", "Viewport", etc.
    # We check for content that looks like extraction data
    SAMPLE_CONTENT=$(head -20 "$CSV_PATH" 2>/dev/null)
    
    # Check for viewport-like data (device-width) which is specific to our XPath task
    if echo "$SAMPLE_CONTENT" | grep -qi "width=device-width"; then
        CSV_HAS_VIEWPORT_DATA="true"
        CSV_HAS_EXTRACTION_DATA="true"
    fi
    
    # Check for charset-like data (utf-8)
    if echo "$SAMPLE_CONTENT" | grep -qi "utf-8"; then
        CSV_HAS_EXTRACTION_DATA="true"
    fi
    
    # Copy for safe reading
    cp "$CSV_PATH" /tmp/result_csv.csv
fi

# --- 2. Find and Analyze Report ---

# Priority 1: Exact expected filename
if [ -f "$REPORTS_DIR/$EXPECTED_REPORT_NAME" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORTS_DIR/$EXPECTED_REPORT_NAME" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_PATH="$REPORTS_DIR/$EXPECTED_REPORT_NAME"
    fi
fi

# Priority 2: Look for txt files
if [ "$REPORT_EXISTS" = "false" ]; then
    LATEST_RPT=$(ls -t "$REPORTS_DIR"/*.txt 2>/dev/null | head -1)
    if [ -n "$LATEST_RPT" ]; then
        FILE_EPOCH=$(stat -c %Y "$LATEST_RPT" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            REPORT_EXISTS="true"
            REPORT_PATH="$LATEST_RPT"
        fi
    fi
fi

if [ "$REPORT_EXISTS" = "true" ]; then
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read content safely
    REPORT_CONTENT=$(cat "$REPORT_PATH" | tr '\n' ' ' | tr '"' "'" | head -c 2000)
    cp "$REPORT_PATH" /tmp/result_report.txt
fi


# --- 3. Export JSON Result ---

python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_path": "$CSV_PATH",
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_columns": """$CSV_COLUMNS""",
    "csv_has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "csv_has_extraction_data": "$CSV_HAS_EXTRACTION_DATA" == "true",
    "csv_has_viewport_data": "$CSV_HAS_VIEWPORT_DATA" == "true",
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_path": "$REPORT_PATH",
    "report_size": $REPORT_SIZE,
    "report_content_preview": """$REPORT_CONTENT""",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/xpath_meta_extraction_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/xpath_meta_extraction_audit_result.json")
PYEOF

echo "=== Export Complete ==="