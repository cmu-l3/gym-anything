#!/bin/bash
# Export script for Target Page Inlink Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Target Page Inlink Audit Result ==="

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
EXPECTED_FILE="$EXPORT_DIR/attic_inlinks.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
FILE_EXISTS="false"
FILE_MODIFIED_DURING_TASK="false"
ROW_COUNT=0
HAS_ANCHOR_TEXT="false"
HAS_TARGET_URL="false"
SF_RUNNING="false"

# 1. Check if Screaming Frog is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 2. Check for the specific output file
if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        FILE_MODIFIED_DURING_TASK="true"
        
        # Analyze CSV content
        # We need to verify it's an Inlinks export, not a generic export
        # Inlinks exports typically have: "From", "To", "Anchor Text", "Status", etc.
        
        # Check headers for "Anchor Text"
        HEADER=$(head -1 "$EXPECTED_FILE" 2>/dev/null || echo "")
        if echo "$HEADER" | grep -qi "Anchor Text"; then
            HAS_ANCHOR_TEXT="true"
        fi
        
        # Check content for the specific target URL in the "To" column (Destination)
        # We search for the specific book fragment
        # We use a loose grep first, then verifier.py will do strict column checks
        if grep -q "a-light-in-the-attic_1000" "$EXPECTED_FILE"; then
            HAS_TARGET_URL="true"
        fi
        
        # Count rows (excluding header)
        TOTAL_LINES=$(wc -l < "$EXPECTED_FILE" || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            ROW_COUNT=$((TOTAL_LINES - 1))
        fi
        
        # Make a copy for verification logic
        cp "$EXPECTED_FILE" /tmp/attic_inlinks_verify.csv
    fi
fi

# 3. Check window title for context (helps debugging)
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 4. Generate JSON result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "file_exists": "$FILE_EXISTS" == "true",
    "file_modified": "$FILE_MODIFIED_DURING_TASK" == "true",
    "row_count": $ROW_COUNT,
    "has_anchor_text_header": "$HAS_ANCHOR_TEXT" == "true",
    "contains_target_url": "$HAS_TARGET_URL" == "true",
    "window_info": """$WINDOW_INFO""",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result generated at /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="