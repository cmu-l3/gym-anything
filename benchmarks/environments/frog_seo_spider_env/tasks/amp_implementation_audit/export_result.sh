#!/bin/bash
# Export result script for AMP Audit task

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting AMP Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/amp_audit_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
AMP_CSV_FOUND="false"
AMP_CSV_PATH=""
AMP_DATA_VALID="false"
AMP_ROW_COUNT=0
REPORT_FOUND="false"
REPORT_CONTENT_VALID="false"
SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Find the AMP CSV Export
# Must be created/modified after task start AND contain "amp" in filename
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Check timestamp
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Check filename contains "amp" (case insensitive)
            if echo "$csv_file" | grep -qi "amp"; then
                AMP_CSV_FOUND="true"
                AMP_CSV_PATH="$csv_file"
                
                # Check content for AMP indicators
                # Look for common headers: "AMP HTML", "Validation Status", "Indexable"
                HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
                if echo "$HEADER" | grep -qi "AMP\|Validation"; then
                    # Check for data rows (not just header)
                    LINE_COUNT=$(wc -l < "$csv_file")
                    if [ "$LINE_COUNT" -gt 1 ]; then
                        AMP_DATA_VALID="true"
                        AMP_ROW_COUNT=$((LINE_COUNT - 1))
                        
                        # Copy for verifier inspection
                        cp "$csv_file" /tmp/amp_export_check.csv 2>/dev/null || true
                    fi
                fi
                break # Stop after finding the first valid-looking AMP file
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Check the Report File
if [ -f "$REPORT_PATH" ]; then
    REPORT_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_FOUND="true"
        # Check size > 0
        if [ -s "$REPORT_PATH" ]; then
            REPORT_CONTENT_VALID="true"
            # Copy for verifier inspection
            cp "$REPORT_PATH" /tmp/amp_report_check.txt 2>/dev/null || true
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "amp_csv_found": $AMP_CSV_FOUND,
    "amp_csv_path": "$AMP_CSV_PATH",
    "amp_data_valid": $AMP_DATA_VALID,
    "amp_row_count": $AMP_ROW_COUNT,
    "report_found": $REPORT_FOUND,
    "report_content_valid": $REPORT_CONTENT_VALID,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="