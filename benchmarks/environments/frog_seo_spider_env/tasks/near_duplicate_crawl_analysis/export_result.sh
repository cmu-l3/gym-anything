#!/bin/bash
# Export script for Near Duplicate Crawl Analysis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Near Duplicate Crawl Result ==="

# 1. Capture final screenshot (visual evidence)
take_screenshot /tmp/task_final.png

# 2. Define expected paths and variables
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
EXPECTED_CSV="$EXPORT_DIR/near_duplicates.csv"
REPORT_PATH="$REPORTS_DIR/similarity_analysis.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Variables to populate for JSON
CSV_FOUND="false"
CSV_PATH=""
HAS_SIMILARITY_COLUMN="false"
HAS_DATA_ROWS="false"
ROW_COUNT=0
TARGET_DOMAIN_FOUND="false"
REPORT_FOUND="false"
REPORT_CONTENT_LENGTH=0
SF_RUNNING="false"

# 3. Check if Screaming Frog is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Find the export file
# Priority: Check exact filename first
CANDIDATE_FILE=""
if [ -f "$EXPECTED_CSV" ]; then
    # Check modification time
    F_MTIME=$(stat -c %Y "$EXPECTED_CSV" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -gt "$TASK_START_EPOCH" ]; then
        CANDIDATE_FILE="$EXPECTED_CSV"
        CSV_FOUND="true"
    fi
fi

# Fallback: If exact file not found, look for ANY recent CSV in exports
if [ "$CSV_FOUND" = "false" ]; then
    # Find newest CSV in export dir modified after task start
    NEWEST_CSV=$(find "$EXPORT_DIR" -name "*.csv" -newermt "@$TASK_START_EPOCH" -type f -printf "%T@ %p\n" | sort -n | tail -1 | awk '{print $2}')
    if [ -n "$NEWEST_CSV" ]; then
        CANDIDATE_FILE="$NEWEST_CSV"
        CSV_FOUND="true"
        echo "Note: Expected file not found, checking $NEWEST_CSV instead."
    fi
fi

CSV_PATH="$CANDIDATE_FILE"

# 5. Analyze CSV content if found
if [ "$CSV_FOUND" = "true" ] && [ -f "$CSV_PATH" ]; then
    # Read header
    HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
    
    # Check for "Similarity" column (Specific to Near Duplicate export)
    # The header usually contains "Similarity" or "Similarity %"
    if echo "$HEADER" | grep -qi "Similarity"; then
        HAS_SIMILARITY_COLUMN="true"
    fi

    # Check for data rows (excluding header)
    ROW_COUNT=$(($(wc -l < "$CSV_PATH" 2>/dev/null || echo "0") - 1))
    if [ "$ROW_COUNT" -gt 0 ]; then
        HAS_DATA_ROWS="true"
    fi

    # Check if data contains target domain
    # Use grep to search for crawler-test.com in the file
    if grep -qi "crawler-test.com" "$CSV_PATH"; then
        TARGET_DOMAIN_FOUND="true"
    fi
fi

# 6. Check Text Report
if [ -f "$REPORT_PATH" ]; then
    R_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$R_MTIME" -gt "$TASK_START_EPOCH" ]; then
        REPORT_FOUND="true"
        REPORT_CONTENT_LENGTH=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
    fi
fi

# 7. Create JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "csv_found": $CSV_FOUND,
    "csv_path": "$CSV_PATH",
    "has_similarity_column": $HAS_SIMILARITY_COLUMN,
    "has_data_rows": $HAS_DATA_ROWS,
    "row_count": $ROW_COUNT,
    "target_domain_found": $TARGET_DOMAIN_FOUND,
    "report_found": $REPORT_FOUND,
    "report_length": $REPORT_CONTENT_LENGTH,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to standard result location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="