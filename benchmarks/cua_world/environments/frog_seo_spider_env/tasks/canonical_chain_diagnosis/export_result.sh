#!/bin/bash
# Export script for Canonical Chain Diagnosis task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Canonical Chain Diagnosis Result ==="

# Capture final state
take_screenshot /tmp/task_end_screenshot.png

REPORTS_DIR="/home/ga/Documents/SEO/reports"
CSV_PATH="$REPORTS_DIR/canonical_chains_audit.csv"
SUMMARY_PATH="$REPORTS_DIR/chain_summary.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# --- Initialize Result Variables ---
CSV_EXISTS="false"
CSV_MODIFIED_DURING_TASK="false"
CSV_HAS_CHAIN_COLUMNS="false"
CSV_ROW_COUNT=0
TARGET_DOMAIN_FOUND="false"

SUMMARY_EXISTS="false"
SUMMARY_MODIFIED_DURING_TASK="false"
SUMMARY_CONTENT=""

SF_RUNNING="false"
WINDOW_INFO=""

# --- Check CSV Report ---
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    
    # Check timestamp
    FILE_EPOCH=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        CSV_MODIFIED_DURING_TASK="true"
        
        # Analyze content
        HEADER=$(head -1 "$CSV_PATH" 2>/dev/null || echo "")
        
        # Check for columns specific to the "Canonical Chains" report
        # Standard exports don't usually have "Chain Length" or "Final Canonical"
        if echo "$HEADER" | grep -qi "Chain Length\|Final Canonical\|Canonical 1"; then
            CSV_HAS_CHAIN_COLUMNS="true"
        fi
        
        # Count data rows
        TOTAL_LINES=$(wc -l < "$CSV_PATH" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 0 ]; then
            CSV_ROW_COUNT=$((TOTAL_LINES - 1))
        fi
        
        # Check domain
        if grep -qi "crawler-test.com" "$CSV_PATH" 2>/dev/null; then
            TARGET_DOMAIN_FOUND="true"
        fi
        
        # Copy for verifier access
        cp "$CSV_PATH" /tmp/exported_chain_report.csv
    fi
fi

# --- Check Summary Text ---
if [ -f "$SUMMARY_PATH" ]; then
    SUMMARY_EXISTS="true"
    FILE_EPOCH=$(stat -c %Y "$SUMMARY_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        SUMMARY_MODIFIED_DURING_TASK="true"
        SUMMARY_CONTENT=$(cat "$SUMMARY_PATH" | head -1)
        cp "$SUMMARY_PATH" /tmp/exported_summary.txt
    fi
fi

# --- Check Application State ---
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# --- Generate JSON Result ---
python3 << PYEOF
import json
import re

summary_content = """$SUMMARY_CONTENT""".strip()
# Extract just the first number found in summary for easier verification
found_numbers = re.findall(r'\d+', summary_content)
summary_count = int(found_numbers[0]) if found_numbers else -1

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_exists": "$CSV_EXISTS" == "true",
    "csv_fresh": "$CSV_MODIFIED_DURING_TASK" == "true",
    "csv_is_chain_report": "$CSV_HAS_CHAIN_COLUMNS" == "true",
    "csv_row_count": $CSV_ROW_COUNT,
    "target_domain_found": "$TARGET_DOMAIN_FOUND" == "true",
    "summary_exists": "$SUMMARY_EXISTS" == "true",
    "summary_fresh": "$SUMMARY_MODIFIED_DURING_TASK" == "true",
    "summary_extracted_count": summary_count,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="