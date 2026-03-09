#!/bin/bash
set -e

echo "=== Exporting Lead Recycling Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_recycle_count.txt 2>/dev/null || echo "0")

# Query Database for the Rules
echo "Querying Vicidial database for recycling rules..."

# We export the rules as a JSON-like structure (or CSV) that we can parse in python
# We select status, delay, max attempts, and active flag
# Using -N (skip headers) and -B (batch/tab-separated)
RAW_DATA=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT status, attempt_delay, attempt_maximum, active 
FROM vicidial_lead_recycle 
WHERE campaign_id = 'SALESCAMP' 
ORDER BY status;
" 2>/dev/null || true)

# Count current rules
CURRENT_COUNT=$(echo "$RAW_DATA" | grep -v "^$" | wc -l)

# Convert raw tab-separated data to JSON array using Python
# This avoids fragile bash string parsing
PYTHON_PARSER=$(cat <<EOF
import sys
import json

raw_data = sys.stdin.read().strip()
rules = []
if raw_data:
    for line in raw_data.split('\n'):
        parts = line.split('\t')
        if len(parts) >= 4:
            rules.append({
                "status": parts[0],
                "attempt_delay": int(parts[1]),
                "attempt_maximum": int(parts[2]),
                "active": parts[3]
            })

result = {
    "task_start": $TASK_START,
    "initial_count": int("$INITIAL_COUNT"),
    "final_count": len(rules),
    "rules": rules,
    "screenshot_path": "/tmp/task_final.png"
}
print(json.dumps(result, indent=2))
EOF
)

# Generate JSON
echo "$RAW_DATA" | python3 -c "$PYTHON_PARSER" > /tmp/task_result.json

# Permission fix for extraction
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="