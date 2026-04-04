#!/bin/bash
echo "=== Exporting Create Custom CI Type result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ==============================================================================
# Query Database for Verification
# ==============================================================================

# 1. Check if CI Type exists
# Returns: citypeid|citypename|parentcitypeid
CITYPE_INFO=$(sdp_db_exec "SELECT citypeid, citypename, parentcitypeid FROM citype WHERE citypename = 'Delivery Drone';" "servicedesk")

# 2. Check Attributes if CI Type was found
ATTRIBUTES_JSON="[]"
if [ -n "$CITYPE_INFO" ]; then
    CITYPE_ID=$(echo "$CITYPE_INFO" | cut -d'|' -f1)
    
    # Query attributes linked to this CI Type
    # Note: Query joins citype_attributes_map -> ciattributedefinition
    # Output format: attributename|datatype
    ATTR_DATA=$(sdp_db_exec "SELECT ad.attributename, ad.datatype FROM ciattributedefinition ad JOIN citype_attributes_map ctam ON ad.attributeid = ctam.attributeid WHERE ctam.citypeid = $CITYPE_ID;" "servicedesk")
    
    # Convert raw SQL output (newline separated) to JSON array
    # Example input:
    # Max Range|CHAR
    # Battery Cycles|BIGINT
    
    if [ -n "$ATTR_DATA" ]; then
        ATTRIBUTES_JSON=$(echo "$ATTR_DATA" | python3 -c '
import sys, json
lines = sys.stdin.read().strip().split("\n")
attrs = []
for line in lines:
    if "|" in line:
        parts = line.split("|")
        attrs.append({"name": parts[0].strip(), "type": parts[1].strip()})
print(json.dumps(attrs))
')
    fi
fi

# Parse CI Type info for JSON
CITYPE_EXISTS="false"
CITYPE_NAME=""
CITYPE_PARENT=""

if [ -n "$CITYPE_INFO" ]; then
    CITYPE_EXISTS="true"
    CITYPE_NAME=$(echo "$CITYPE_INFO" | cut -d'|' -f2)
    CITYPE_PARENT=$(echo "$CITYPE_INFO" | cut -d'|' -f3)
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "citype_exists": $CITYPE_EXISTS,
    "citype_name": "$CITYPE_NAME",
    "citype_parent_id": "$CITYPE_PARENT",
    "attributes": $ATTRIBUTES_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="