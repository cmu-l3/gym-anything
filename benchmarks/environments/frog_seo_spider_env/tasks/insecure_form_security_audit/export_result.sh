#!/bin/bash
# Export script for Insecure Form Security Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Insecure Form Security Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

SECURITY_CSV=""
TARGET_DOMAIN_FOUND="false"
HAS_SECURITY_URLS="false"
CSV_ROW_COUNT=0
SF_RUNNING="false"

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title info
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# Look for CSVs created after task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            echo "Analyzing new CSV: $csv_file"
            
            # Check content for target domain
            if grep -qi "crawler-test.com" "$csv_file"; then
                TARGET_DOMAIN_FOUND="true"
            fi

            # Check for specific security URL patterns known to exist on crawler-test.com
            # Examples: non_secure_form, password, text_field
            if grep -qiE "non_secure_form|password|text_field|insecure" "$csv_file"; then
                HAS_SECURITY_URLS="true"
                SECURITY_CSV="$csv_file"
                
                # Count rows (minus header)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CSV_ROW_COUNT=$((TOTAL_LINES - 1))
                
                # If we found a good candidate, break (prioritize specific security exports)
                break
            fi
            
            # Fallback: if we found domain but not specific security keywords yet, keep looking
            # but remember this file just in case
            if [ "$TARGET_DOMAIN_FOUND" == "true" ] && [ -z "$SECURITY_CSV" ]; then
                SECURITY_CSV="$csv_file"
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CSV_ROW_COUNT=$((TOTAL_LINES - 1))
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# Write result JSON using Python
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "security_csv_found": len("$SECURITY_CSV") > 0,
    "security_csv_path": "$SECURITY_CSV",
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "has_security_urls": "$HAS_SECURITY_URLS" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/insecure_form_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/insecure_form_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="