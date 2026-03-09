#!/bin/bash
# Export script for Legacy Meta Keywords Cleanup Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Result ==="

# Trap errors to ensure result file is created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Define Variables
EXPECTED_PATH="/home/ga/Documents/SEO/exports/meta_keywords_audit.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
SF_RUNNING="false"
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
VALID_DOMAIN="false"
HAS_HITS="false"
TOTAL_ROWS=0
HIT_COUNT=0

# 3. Check App Status
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 4. Analyze Export File
if [ -f "$EXPECTED_PATH" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
        
        # Analyze content
        # Check for target domain
        if grep -qi "crawler-test.com" "$EXPECTED_PATH"; then
            VALID_DOMAIN="true"
        fi
        
        # Count data rows (excluding header)
        TOTAL_ROWS=$(wc -l < "$EXPECTED_PATH")
        TOTAL_ROWS=$((TOTAL_ROWS - 1))
        
        # Check for Hits (Custom Search exports usually have a 'Count' or 'Contains' column)
        # We need to verify that at least one row has a match > 0.
        # Screaming Frog Custom Search export format: Address, Status Code, Status, Contains '...', Count
        # If the search failed (e.g. searching Text instead of HTML), Count will be 0.
        
        # We look for lines that do NOT end with ",0" or ",0.0" if Count is the last column
        # Or simply grep for the search term if it prints the found text
        
        # Use python for robust CSV parsing
        HIT_COUNT=$(python3 << PYEOF
import csv
import sys

try:
    with open("$EXPECTED_PATH", "r", encoding="utf-8", errors="ignore") as f:
        reader = csv.reader(f)
        headers = next(reader, [])
        count = 0
        for row in reader:
            # Look for columns that might indicate a hit count (usually named after search term or 'Count')
            # A hit is usually a non-zero integer or the presence of the string
            row_str = ",".join(row).lower()
            
            # Simple heuristic: if any cell converts to int > 0, or boolean 'true'
            has_val = False
            for cell in row:
                if cell.strip().isdigit() and int(cell) > 0:
                    has_val = True
                    break
            
            if has_val:
                count += 1
        print(count)
except Exception:
    print("0")
PYEOF
)
        
        if [ "$HIT_COUNT" -gt 0 ]; then
            HAS_HITS="true"
        fi
    fi
fi

# 5. Get Window Info (for debugging/verification)
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming\|spider" | head -1 | sed 's/"/\\"/g')

# 6. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "valid_domain": $VALID_DOMAIN,
    "has_hits": $HAS_HITS,
    "total_rows": $TOTAL_ROWS,
    "hit_count": $HIT_COUNT,
    "window_info": "$WINDOW_INFO",
    "timestamp": "$(date -Iseconds)"
}
EOF

# 7. Save Result securely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="