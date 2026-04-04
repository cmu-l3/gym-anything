#!/bin/bash
# Export script for Image Asset Format Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Image Asset Format Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
EXPECTED_CSV_NAME="image_inventory.csv"
EXPECTED_REPORT_NAME="image_optimization_strategy.txt"

# 3. Analyze CSV Export
CSV_FOUND="false"
CSV_PATH=""
CSV_ROW_COUNT=0
IS_IMAGE_DATA="false"
HAS_TARGET_DOMAIN="false"
FORMATS_DETECTED=""

# Find the specific file or the newest CSV
if [ -f "$EXPORT_DIR/$EXPECTED_CSV_NAME" ]; then
    CSV_PATH="$EXPORT_DIR/$EXPECTED_CSV_NAME"
else
    # Fallback: check newest CSV if exact name not found
    CSV_PATH=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
fi

if [ -n "$CSV_PATH" ] && [ -f "$CSV_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    
    # Verify file was modified/created during task
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_FOUND="true"
        
        # Count rows (minus header)
        TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        fi

        # Check content for Image-specific headers/data
        # Standard SF Image export has "Content Type", "Size", "Dimensions"
        # Or check extensions in the Address column
        HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
        SAMPLE=$(head -20 "$CSV_PATH" 2>/dev/null || echo "")

        if echo "$HEADER" | grep -qi "Content Type\|Size\|Dimensions\|Image"; then
            IS_IMAGE_DATA="true"
        elif echo "$SAMPLE" | grep -qi "\.jpg\|\.jpeg\|\.png\|\.gif\|\.webp"; then
            IS_IMAGE_DATA="true"
        fi

        # Check for target domain
        if grep -qi "books.toscrape.com" "$CSV_PATH" 2>/dev/null; then
            HAS_TARGET_DOMAIN="true"
        fi
        
        # Check for specific formats present
        if grep -qi "\.jpg\|\.jpeg" "$CSV_PATH"; then FORMATS_DETECTED="${FORMATS_DETECTED}JPG "; fi
        if grep -qi "\.png" "$CSV_PATH"; then FORMATS_DETECTED="${FORMATS_DETECTED}PNG "; fi
        if grep -qi "\.gif" "$CSV_PATH"; then FORMATS_DETECTED="${FORMATS_DETECTED}GIF "; fi
    fi
fi

# 4. Analyze Report
REPORT_FOUND="false"
REPORT_PATH="$REPORTS_DIR/$EXPECTED_REPORT_NAME"
REPORT_SIZE=0
REPORT_HAS_COUNTS="false"
REPORT_HAS_SIZE_ANALYSIS="false"
REPORT_HAS_RECOMMENDATION="false"

if [ -f "$REPORT_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_FOUND="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        
        CONTENT=$(cat "$REPORT_PATH" | tr '[:upper:]' '[:lower:]')
        
        # Check for numeric counts (simple regex for digits)
        if [[ "$CONTENT" =~ [0-9]+ ]]; then
            REPORT_HAS_COUNTS="true"
        fi
        
        # Check for size analysis keywords
        if [[ "$CONTENT" =~ (kb|mb|bytes|large|heavy|size) ]]; then
            REPORT_HAS_SIZE_ANALYSIS="true"
        fi
        
        # Check for recommendation keywords
        if [[ "$CONTENT" =~ (recommend|optimize|convert|webp|compress) ]]; then
            REPORT_HAS_RECOMMENDATION="true"
        fi
    fi
fi

# 5. Check System State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 6. Generate JSON Result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_found": "$CSV_FOUND" == "true",
    "csv_path": "$CSV_PATH",
    "csv_row_count": $CSV_ROW_COUNT,
    "is_image_data": "$IS_IMAGE_DATA" == "true",
    "has_target_domain": "$HAS_TARGET_DOMAIN" == "true",
    "formats_detected": "$FORMATS_DETECTED".strip(),
    "report_found": "$REPORT_FOUND" == "true",
    "report_path": "$REPORT_PATH",
    "report_size": $REPORT_SIZE,
    "report_has_counts": "$REPORT_HAS_COUNTS" == "true",
    "report_has_size_analysis": "$REPORT_HAS_SIZE_ANALYSIS" == "true",
    "report_has_recommendation": "$REPORT_HAS_RECOMMENDATION" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result generated at /tmp/task_result.json")
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true
echo "=== Export Complete ==="