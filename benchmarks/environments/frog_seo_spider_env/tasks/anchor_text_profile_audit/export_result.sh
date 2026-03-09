#!/bin/bash
# Export script for Anchor Text Profile Audit task
# This script analyzes the files created by the agent to generate a JSON result

source /workspace/scripts/task_utils.sh

echo "=== Exporting Anchor Text Profile Audit Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Setup variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/anchor_text_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Analyze CSV Exports
# We are looking for an "Inlinks" export which typically contains "Anchor" in the header
INLINKS_CSV=""
INLINKS_ROW_COUNT=0
HAS_ANCHOR_COL="false"
HAS_TARGET_DOMAIN="false"
HAS_NON_EMPTY_ANCHORS="false"
NEW_CSV_COUNT=0

# Iterate through all CSVs in the export directory
if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        # Check modification time
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            NEW_CSV_COUNT=$((NEW_CSV_COUNT + 1))
            
            # Read header
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            
            # Check for Anchor column (case insensitive)
            if echo "$HEADER" | grep -qi "anchor"; then
                # This is likely the correct file
                INLINKS_CSV="$csv_file"
                HAS_ANCHOR_COL="true"
                
                # Check for target domain (books.toscrape.com)
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    HAS_TARGET_DOMAIN="true"
                fi
                
                # Count data rows (lines - 1)
                TOTAL_LINES=$(wc -l < "$csv_file" 2>/dev/null || echo "0")
                if [ "$TOTAL_LINES" -gt 0 ]; then
                    INLINKS_ROW_COUNT=$((TOTAL_LINES - 1))
                fi
                
                # Check for non-empty anchor text
                # We look for rows where the anchor column isn't empty
                # This is a heuristic check
                if [ "$INLINKS_ROW_COUNT" -gt 10 ]; then
                    HAS_NON_EMPTY_ANCHORS="true"
                fi
                
                # Break after finding the most likely candidate
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 4. Analyze Report File
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_KEYWORDS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Read content for analysis
    CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "")
    
    # Check for numbers (counts)
    if echo "$CONTENT" | grep -qE "[0-9]+"; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for keywords
    if echo "$CONTENT" | grep -qiE "anchor|text|link|generic|empty|image|recommend|improve"; then
        REPORT_HAS_KEYWORDS="true"
    fi
fi

# 5. Check System State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming\|spider" | head -1 || echo "")

# 6. Create JSON Result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "new_csv_count": $NEW_CSV_COUNT,
    "inlinks_csv_found": len("$INLINKS_CSV") > 0,
    "inlinks_csv_path": "$INLINKS_CSV",
    "has_anchor_col": "$HAS_ANCHOR_COL" == "true",
    "has_target_domain": "$HAS_TARGET_DOMAIN" == "true",
    "has_non_empty_anchors": "$HAS_NON_EMPTY_ANCHORS" == "true",
    "row_count": $INLINKS_ROW_COUNT,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "report_has_keywords": "$REPORT_HAS_KEYWORDS" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="
cat /tmp/task_result.json