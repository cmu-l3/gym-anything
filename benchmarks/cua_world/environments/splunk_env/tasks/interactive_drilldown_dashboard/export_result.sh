#!/bin/bash
echo "=== Exporting interactive_drilldown_dashboard result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve and parse dashboard XML via REST API
echo "Checking dashboards..."
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess

try:
    with open('/tmp/initial_dashboards.json', 'r') as f:
        initial_dashboards = json.load(f)
except:
    initial_dashboards = []

result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0'],
    capture_output=True, text=True
)

analysis = {
    "dashboard_exists": False,
    "actual_name": "",
    "has_base_search": False,
    "has_drilldown": False,
    "has_token_set": False,
    "has_token_usage": False,
    "xml_data_preview": "",
    "new_dashboards_found": 0
}

try:
    data = json.loads(result.stdout)
    entries = data.get('entry', [])
    
    target_entry = None
    new_dashboards_count = 0
    
    # 1. Try to find by exact name match (case-insensitive)
    for entry in entries:
        name = entry.get('name', '')
        if name not in initial_dashboards:
            new_dashboards_count += 1
            
        if name.lower() == 'targeted_user_investigation':
            target_entry = entry
            break
            
    # 2. Fallback: if exact name not found, check newly created dashboards
    if not target_entry:
        for entry in entries:
            name = entry.get('name', '')
            if name not in initial_dashboards:
                xml_content = entry.get('content', {}).get('eai:data', '').lower()
                # Pick the first new dashboard that has drilldown
                if '<drilldown>' in xml_content:
                    target_entry = entry
                    break

    analysis["new_dashboards_found"] = new_dashboards_count

    if target_entry:
        analysis["dashboard_exists"] = True
        analysis["actual_name"] = target_entry.get('name', '')
        xml_content = target_entry.get('content', {}).get('eai:data', '')
        analysis["xml_data_preview"] = xml_content[:500] + "..." if len(xml_content) > 500 else xml_content
        
        xml_lower = xml_content.lower()
        
        # Check for base query using security logs and user field
        if 'security_logs' in xml_lower and 'user' in xml_lower:
            analysis["has_base_search"] = True
            
        # Check for drilldown element
        if '<drilldown>' in xml_lower:
            analysis["has_drilldown"] = True
            
        # Check if the specific token is set
        if 'token="clicked_user"' in xml_lower or "token='clicked_user'" in xml_lower or "<set token=\"clicked_user\">" in xml_lower:
            analysis["has_token_set"] = True
            
        # Check if the token is used as a substitution variable in another query
        if '$clicked_user$' in xml_lower:
            analysis["has_token_usage"] = True
            
except Exception as e:
    analysis["error"] = str(e)

print(json.dumps(analysis))
PYEOF
)

# Get timing information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="