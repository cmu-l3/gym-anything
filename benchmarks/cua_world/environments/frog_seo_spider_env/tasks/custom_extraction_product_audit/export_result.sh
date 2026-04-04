#!/bin/bash
# Export script for Custom Extraction Product Audit task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Custom Extraction Product Audit Result ==="

take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Find all CSVs created after task start
CUSTOM_CSV=""
INTERNAL_CSV=""
CUSTOM_HAS_PRICE="false"
CUSTOM_HAS_RATING="false"
CUSTOM_ROW_COUNT=0
INTERNAL_ROW_COUNT=0
TARGET_DOMAIN_FOUND="false"
SF_RUNNING="false"
WINDOW_INFO=""

# Check if SF is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Get window title
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider\|books.toscrape\|toscrape" | head -1 || echo "")

# Find CSV files created after task start
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Read first 5 lines to inspect headers and content
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            SAMPLE=$(head -5 "$csv_file" 2>/dev/null || echo "")

            # Check if this is a custom extraction CSV
            # Custom extraction CSVs have columns like "Custom Extraction 1" or user-named columns
            # and contain price data (£ symbol) or rating class values
            if echo "$SAMPLE" | grep -qi "£\|price_color\|star-rating\|Custom Extraction"; then
                CUSTOM_CSV="$csv_file"
                # Check for pound price values (£X.XX)
                if grep -q "£" "$csv_file" 2>/dev/null; then
                    CUSTOM_HAS_PRICE="true"
                fi
                # Check for rating class values
                if grep -qi "star-rating\|One\|Two\|Three\|Four\|Five" "$csv_file" 2>/dev/null; then
                    CUSTOM_HAS_RATING="true"
                fi
                # Count data rows (total - 1 header)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                CUSTOM_ROW_COUNT=$((TOTAL_LINES - 1))
                # Check for target domain
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_FOUND="true"
                fi
            fi

            # Check if this is a standard internal HTML report
            # Internal reports have columns: Title 1, Meta Description 1, H1-1
            if echo "$HEADER" | grep -qi "Title 1\|Meta Description 1\|H1-1"; then
                INTERNAL_CSV="$csv_file"
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "1")
                INTERNAL_ROW_COUNT=$((TOTAL_LINES - 1))
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_FOUND="true"
                fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# Count total new CSVs
NEW_CSV_COUNT=$(find "$EXPORT_DIR" -name "*.csv" -newer /tmp/task_start_time -type f 2>/dev/null | wc -l || echo "0")

# Check window title for domain confirmation
WINDOW_HAS_TARGET="false"
if echo "$WINDOW_INFO" | grep -qi "books.toscrape\|toscrape"; then
    WINDOW_HAS_TARGET="true"
fi

# Write result JSON using Python for safety
python3 << PYEOF
import json, os

result = {
    "sf_running": $SF_RUNNING == "true",
    "window_has_target_domain": "$WINDOW_HAS_TARGET" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "custom_csv_found": len("$CUSTOM_CSV") > 0,
    "custom_csv_path": "$CUSTOM_CSV",
    "custom_has_price_data": "$CUSTOM_HAS_PRICE" == "true",
    "custom_has_rating_data": "$CUSTOM_HAS_RATING" == "true",
    "custom_row_count": $CUSTOM_ROW_COUNT,
    "internal_csv_found": len("$INTERNAL_CSV") > 0,
    "internal_csv_path": "$INTERNAL_CSV",
    "internal_row_count": $INTERNAL_ROW_COUNT,
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/custom_extraction_product_audit_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/custom_extraction_product_audit_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
