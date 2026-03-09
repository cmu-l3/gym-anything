#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Configure Lost Reasons result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Export current Lost Reasons data to JSON using Python/XMLRPC
# This ensures we get clean data regardless of UI state
echo "Querying Odoo database for lost reasons..."
python3 - <<PYEOF > /tmp/raw_reasons.json
import xmlrpc.client
import json
import sys

try:
    common = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/common')
    uid = common.authenticate('odoodb', 'admin', 'admin', {})
    models = xmlrpc.client.ServerProxy('http://localhost:8069/xmlrpc/2/object')

    # Get all lost reasons
    reasons = models.execute_kw('odoodb', uid, 'admin', 'crm.lost.reason', 'search_read',
        [[]], {'fields': ['id', 'name', 'active']})
    
    print(json.dumps(reasons))

except Exception as e:
    print(json.dumps({"error": str(e)}))
    sys.exit(1)
PYEOF

# Construct the final result JSON
# We include the raw list and the counts
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "current_reasons": $(cat /tmp/raw_reasons.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="