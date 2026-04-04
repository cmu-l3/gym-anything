#!/bin/bash
# Export script for Non-HTML Document Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Non-HTML Document Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Configuration
EXPECTED_CSV="/home/ga/Documents/SEO/exports/pdf_inventory.csv"
EXPECTED_REPORT="/home/ga/Documents/SEO/reports/pdf_audit_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to track status
SF_RUNNING="false"
CSV_EXISTS="false"
CSV_MODIFIED_AFTER_START="false"
CSV_HAS_PDF="false"
CSV_HAS_TARGET_DOMAIN="false"
CSV_ROW_COUNT=0
REPORT_EXISTS="false"
REPORT_MODIFIED_AFTER_START="false"
REPORT_HAS_COUNT="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title for VLM context
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- Verify CSV Output ---
if [ -f "$EXPECTED_CSV" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_AFTER_START="true"
    fi

    # Check content
    # Count rows (excluding header)
    TOTAL_LINES=$(wc -l < "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$TOTAL_LINES" -gt 1 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi

    # Check for PDF extension or MIME type
    if grep -qi "\.pdf\|application/pdf" "$EXPECTED_CSV"; then
        CSV_HAS_PDF="true"
    fi

    # Check for target domain
    if grep -qi "crawler-test.com" "$EXPECTED_CSV"; then
        CSV_HAS_TARGET_DOMAIN="true"
    fi
    
    # Copy for verification
    cp "$EXPECTED_CSV" /tmp/pdf_inventory_verification.csv 2>/dev/null || true
fi

# --- Verify Report Output ---
if [ -f "$EXPECTED_REPORT" ]; then
    REPORT_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_REPORT" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_AFTER_START="true"
    fi

    # Check for numbers/counts
    if grep -qE "[0-9]+" "$EXPECTED_REPORT"; then
        REPORT_HAS_COUNT="true"
    fi
    
    # Copy for verification
    cp "$EXPECTED_REPORT" /tmp/pdf_report_verification.txt 2>/dev/null || true
fi

# Create JSON result
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_modified": "$CSV_MODIFIED_AFTER_START" == "true",
    "csv_has_pdf": "$CSV_HAS_PDF" == "true",
    "csv_has_target_domain": "$CSV_HAS_TARGET_DOMAIN" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_modified": "$REPORT_MODIFIED_AFTER_START" == "true",
    "report_has_count": "$REPORT_HAS_COUNT" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/non_html_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/non_html_audit_result.json")
PYEOF

echo "=== Export Complete ==="