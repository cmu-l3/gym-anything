#!/bin/bash
# Export script for Sitemap Status Integrity Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Sitemap Audit Result ==="

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# Paths
EXPORT_FILE="/home/ga/Documents/SEO/exports/sitemap_audit_data.csv"
REPORT_FILE="/home/ga/Documents/SEO/reports/sitemap_remediation.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# --- Analysis Variables ---
EXPORT_EXISTS="false"
EXPORT_MODIFIED_DURING_TASK="false"
EXPORT_HAS_STATUS_COL="false"
EXPORT_HAS_404_URL="false"
EXPORT_ROW_COUNT=0

REPORT_EXISTS="false"
REPORT_MODIFIED_DURING_TASK="false"
REPORT_HAS_COUNTS="false"
REPORT_HAS_404_MENTION="false"
REPORT_HAS_SPECIFIC_URL="false"
SF_RUNNING="false"

# --- Check Screaming Frog State ---
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- Verify Export CSV ---
if [ -f "$EXPORT_FILE" ]; then
    EXPORT_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        EXPORT_MODIFIED_DURING_TASK="true"
    fi
    
    # Count rows (minus header)
    EXPORT_ROW_COUNT=$(($(wc -l < "$EXPORT_FILE") - 1))
    
    # Check Content
    HEADER=$(head -1 "$EXPORT_FILE" 2>/dev/null || echo "")
    CONTENT=$(cat "$EXPORT_FILE" 2>/dev/null || echo "")
    
    if echo "$HEADER" | grep -qi "Status Code"; then
        EXPORT_HAS_STATUS_COL="true"
    fi
    
    # Check for the specific 404 URL we put in the sitemap
    if echo "$CONTENT" | grep -q "crawler-test.com/status_codes/404"; then
        EXPORT_HAS_404_URL="true"
    fi
fi

# --- Verify Remediation Report ---
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED_DURING_TASK="true"
    fi
    
    CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | tr '[:upper:]' '[:lower:]' || echo "")
    
    # Check for numbers (counts)
    if echo "$CONTENT" | grep -qE "[0-9]"; then
        REPORT_HAS_COUNTS="true"
    fi
    
    # Check for mentions of 404
    if echo "$CONTENT" | grep -q "404"; then
        REPORT_HAS_404_MENTION="true"
    fi
    
    # Check for specific URL
    if echo "$CONTENT" | grep -q "crawler-test.com/status_codes/404"; then
        REPORT_HAS_SPECIFIC_URL="true"
    fi
fi

# --- Create Result JSON ---
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_info": """$WINDOW_INFO""",
    
    "export_exists": $EXPORT_EXISTS == "true",
    "export_fresh": $EXPORT_MODIFIED_DURING_TASK == "true",
    "export_row_count": $EXPORT_ROW_COUNT,
    "export_valid_cols": $EXPORT_HAS_STATUS_COL == "true",
    "export_found_target": $EXPORT_HAS_404_URL == "true",
    
    "report_exists": $REPORT_EXISTS == "true",
    "report_fresh": $REPORT_MODIFIED_DURING_TASK == "true",
    "report_has_counts": $REPORT_HAS_COUNTS == "true",
    "report_mentions_404": $REPORT_HAS_404_MENTION == "true",
    "report_identifies_url": $REPORT_HAS_SPECIFIC_URL == "true",
    
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="