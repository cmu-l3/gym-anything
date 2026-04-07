#!/bin/bash
echo "=== Exporting security_investigation_workbook result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get current dashboards
echo "Checking dashboards..."
DASHBOARDS_TEMP=$(mktemp /tmp/dashboards.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$DASHBOARDS_TEMP" 2>/dev/null

# Analyze dashboards for the required workbook
DASHBOARD_ANALYSIS=$(python3 - "$DASHBOARDS_TEMP" << 'PYEOF'
import sys, json, re

def normalize_name(name):
    """Normalize dashboard name for comparison."""
    return name.lower().replace(' ', '_').replace('-', '_')

try:
    with open(sys.argv[1], 'r') as f:
        data = json.load(f)
    entries = data.get('entry', [])

    # Load initial dashboards to distinguish pre-existing vs new
    try:
        with open('/tmp/initial_dashboards.json', 'r') as f:
            initial_names = json.loads(f.read())
    except:
        initial_names = []

    expected_name_normalized = "security_investigation_workbook"
    
    found_dashboard = False
    dashboard_name = ""
    is_new = False
    xml_data = ""
    input_count = 0
    panel_count = 0
    token_usage_count = 0
    references_logs = False
    
    new_dashboards = []

    for entry in entries:
        name = entry.get('name', '')
        content = entry.get('content', {})
        eai_data = content.get('eai:data', '')  # XML content
        
        is_entry_new = name not in initial_names
        if is_entry_new:
            new_dashboards.append(name)
            
        name_normalized = normalize_name(name)
        
        # Look for our specific dashboard
        if name_normalized == expected_name_normalized:
            found_dashboard = True
            dashboard_name = name
            is_new = is_entry_new
            xml_data = eai_data
            
            # Analyze XML structure (SimpleXML standard)
            # Count inputs (<input type="text">, <input type="time">, etc.)
            inputs = re.findall(r'<input\b[^>]*>', eai_data, re.IGNORECASE)
            input_count = len(inputs)
            
            # Count panels
            panels = re.findall(r'<panel\b[^>]*>', eai_data, re.IGNORECASE)
            panel_count = len(panels)
            
            # Find token usage in queries (e.g., $target_ip$)
            # Look inside <query> or <search> tags specifically, or just count $...$ matches
            token_matches = re.findall(r'\$[a-zA-Z0-9_]+\$', eai_data)
            # Filter out known built-in tokens if necessary, but generally any $ token is good
            token_usage_count = len(token_matches)
            
            # Check for required indexes
            eai_data_lower = eai_data.lower()
            references_logs = 'security_logs' in eai_data_lower or 'web_logs' in eai_data_lower
            
            break

    # Fallback: if exact name not found, take the best new dashboard to provide partial feedback
    if not found_dashboard and new_dashboards:
        for entry in entries:
            name = entry.get('name', '')
            if name in new_dashboards:
                eai_data = entry.get('content', {}).get('eai:data', '')
                eai_data_lower = eai_data.lower()
                
                # Check if it has workbook characteristics
                if '<input' in eai_data_lower and '<panel' in eai_data_lower:
                    found_dashboard = True
                    dashboard_name = name
                    is_new = True
                    xml_data = eai_data
                    input_count = len(re.findall(r'<input\b[^>]*>', eai_data, re.IGNORECASE))
                    panel_count = len(re.findall(r'<panel\b[^>]*>', eai_data, re.IGNORECASE))
                    token_usage_count = len(re.findall(r'\$[a-zA-Z0-9_]+\$', eai_data))
                    references_logs = 'security_logs' in eai_data_lower or 'web_logs' in eai_data_lower
                    break

    result = {
        "found_dashboard": found_dashboard,
        "dashboard_name": dashboard_name,
        "is_new": is_new,
        "input_count": input_count,
        "panel_count": panel_count,
        "token_usage_count": token_usage_count,
        "references_logs": references_logs,
        "new_dashboards": new_dashboards
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({
        "found_dashboard": False,
        "error": str(e)
    }))
PYEOF
)
rm -f "$DASHBOARDS_TEMP"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dashboard_analysis": ${DASHBOARD_ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="