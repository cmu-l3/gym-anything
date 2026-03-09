#!/bin/bash
# Export script for Unsafe Cross-Origin Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Unsafe Cross-Origin Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

# Configuration
CSV_PATH="/home/ga/Documents/SEO/exports/unsafe_links.csv"
REPORT_PATH="/home/ga/Documents/SEO/reports/security_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Analyze CSV
CSV_EXISTS="false"
CSV_MODIFIED="false"
CSV_ROW_COUNT=0
CSV_HAS_TARGET_COL="false"
CSV_HAS_REL_COL="false"
CSV_CONTAINS_DOMAIN="false"
CSV_CONTAINS_UNSAFE="false"

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check modification time
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED="true"
    fi
    
    # Copy for verification
    cp "$CSV_PATH" /tmp/unsafe_links_verify.csv
    
    # Analyze content
    HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    
    # Check columns (Security tab export typically has 'Target' and 'Rel')
    if echo "$HEADER" | grep -qi "Target"; then CSV_HAS_TARGET_COL="true"; fi
    if echo "$HEADER" | grep -qi "Rel"; then CSV_HAS_REL_COL="true"; fi
    
    # Check domain
    if grep -qi "crawler-test.com" "$CSV_PATH"; then CSV_CONTAINS_DOMAIN="true"; fi
    
    # Check for evidence of unsafe links (target blank without noopener)
    # The CSV value for 'Target' column should be '_blank'
    if grep -qi "_blank" "$CSV_PATH"; then CSV_CONTAINS_UNSAFE="true"; fi
    
    # Count data rows (subtract 1 for header)
    TOTAL_LINES=$(wc -l < "$CSV_PATH" || echo "0")
    if [ "$TOTAL_LINES" -gt 0 ]; then
        CSV_ROW_COUNT=$((TOTAL_LINES - 1))
    fi
fi

# 2. Analyze Report
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
REPORT_VALUE=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_MODIFIED="true"
    fi
    
    # Extract the first number found in the file
    REPORT_VALUE=$(grep -oE "[0-9]+" "$REPORT_PATH" | head -1 || echo "")
fi

# 3. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Write JSON result
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "csv_exists": $CSV_EXISTS,
    "csv_modified": $CSV_MODIFIED,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_has_target_col": $CSV_HAS_TARGET_COL,
    "csv_has_rel_col": $CSV_HAS_REL_COL,
    "csv_contains_domain": $CSV_CONTAINS_DOMAIN,
    "csv_contains_unsafe": $CSV_CONTAINS_UNSAFE,
    "report_exists": $REPORT_EXISTS,
    "report_modified": $REPORT_MODIFIED,
    "report_value": "$REPORT_VALUE"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported result:")
print(json.dumps(result, indent=2))
PYEOF

# Clean permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="