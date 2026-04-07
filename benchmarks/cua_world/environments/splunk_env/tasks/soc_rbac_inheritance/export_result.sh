#!/bin/bash
echo "=== Exporting soc_rbac_inheritance result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all roles using Splunk REST API
echo "Querying Splunk for role configurations..."
ROLES_TEMP=$(mktemp /tmp/roles.XXXXXX.json)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/services/authorization/roles?output_mode=json&count=0" \
    > "$ROLES_TEMP" 2>/dev/null

# Parse the REST API response specifically for our target roles
ROLE_ANALYSIS=$(python3 - "$ROLES_TEMP" << 'PYEOF'
import sys, json

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    
    entries = data.get('entry', [])
    tier1_data = None
    tier2_data = None
    
    for e in entries:
        name = e.get('name')
        if name == 'soc_tier1':
            tier1_data = e.get('content', {})
        elif name == 'soc_tier2':
            tier2_data = e.get('content', {})
            
    result = {
        "tier1_found": tier1_data is not None,
        "tier1_config": tier1_data or {},
        "tier2_found": tier2_data is not None,
        "tier2_config": tier2_data or {}
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "error": str(e),
        "tier1_found": False,
        "tier2_found": False
    }))
PYEOF
)
rm -f "$ROLES_TEMP"

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "role_analysis": ${ROLE_ANALYSIS},
    "task_start_time": $(cat /tmp/task_start_time.txt 2>/dev/null || echo "0"),
    "task_end_time": $(cat /tmp/task_end_time.txt 2>/dev/null || echo "0"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="