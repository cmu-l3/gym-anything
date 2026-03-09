#!/bin/bash
# Export script for Internal Link Equity Audit task
# This script analyzes the files created by the agent to verify the task.

source /workspace/scripts/task_utils.sh

echo "=== Exporting Internal Link Equity Audit Result ==="

# Trap errors
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# Take final screenshot
take_screenshot /tmp/task_final.png

# Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORT_PATH="/home/ga/Documents/SEO/reports/internal_links_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 1. Analyze CSV Exports
# We look for a CSV created AFTER task start that looks like an "All Inlinks" export.
# Key columns in Inlinks export: Source, Destination, Anchor
# Key columns in Standard export (wrong one): Address, Content, Title 1

INLINKS_CSV_FOUND="false"
INLINKS_CSV_PATH=""
INLINKS_ROW_COUNT=0
HAS_SOURCE_COL="false"
HAS_DEST_COL="false"
HAS_ANCHOR_COL="false"
TARGET_DOMAIN_IN_CSV="false"

if [ -d "$EXPORT_DIR" ]; then
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Check if file is new (modified after task start)
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            
            # Check for Inlinks-specific columns
            # Screaming Frog Inlinks exports usually have "Source", "Destination", "Anchor"
            if echo "$HEADER" | grep -qi "Source" && echo "$HEADER" | grep -qi "Destination" && echo "$HEADER" | grep -qi "Anchor"; then
                INLINKS_CSV_FOUND="true"
                INLINKS_CSV_PATH="$csv_file"
                HAS_SOURCE_COL="true"
                HAS_DEST_COL="true"
                HAS_ANCHOR_COL="true"
                
                # Count rows (excluding header)
                INLINKS_ROW_COUNT=$(($(wc -l < "$csv_file" 2>/dev/null || echo "1") - 1))
                
                # Check for target domain data
                if grep -qi "books.toscrape.com" "$csv_file" 2>/dev/null; then
                    TARGET_DOMAIN_IN_CSV="true"
                fi
                
                # Stop after finding the first valid candidate
                break
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 2. Analyze Report
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_URLS="false"
REPORT_HAS_ANCHOR_TERM="false"
REPORT_HAS_RECOMMENDATIONS="false"

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Check content
    CONTENT=$(cat "$REPORT_PATH")
    
    # Check for numbers (counts)
    if echo "$CONTENT" | grep -qE "[0-9]+"; then
        REPORT_HAS_NUMBERS="true"
    fi
    
    # Check for URLs (referencing the site)
    if echo "$CONTENT" | grep -qE "http|www\.|books\.toscrape"; then
        REPORT_HAS_URLS="true"
    fi
    
    # Check for anchor text analysis keywords
    if echo "$CONTENT" | grep -qi "anchor"; then
        REPORT_HAS_ANCHOR_TERM="true"
    fi
    
    # Check for recommendation keywords
    if echo "$CONTENT" | grep -qiE "recommend|suggest|improve|should|fix"; then
        REPORT_HAS_RECOMMENDATIONS="true"
    fi
fi

# 3. Check App State
SF_RUNNING="false"
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Write result to JSON
python3 << PYEOF
import json

result = {
    "sf_running": $SF_RUNNING,
    "inlinks_csv_found": $INLINKS_CSV_FOUND,
    "inlinks_csv_path": "$INLINKS_CSV_PATH",
    "inlinks_row_count": $INLINKS_ROW_COUNT,
    "has_source_col": $HAS_SOURCE_COL,
    "has_dest_col": $HAS_DEST_COL,
    "has_anchor_col": $HAS_ANCHOR_COL,
    "target_domain_in_csv": $TARGET_DOMAIN_IN_CSV,
    "report_exists": $REPORT_EXISTS,
    "report_size_bytes": $REPORT_SIZE,
    "report_has_numbers": $REPORT_HAS_NUMBERS,
    "report_has_urls": $REPORT_HAS_URLS,
    "report_has_anchor_term": $REPORT_HAS_ANCHOR_TERM,
    "report_has_recommendations": $REPORT_HAS_RECOMMENDATIONS,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="