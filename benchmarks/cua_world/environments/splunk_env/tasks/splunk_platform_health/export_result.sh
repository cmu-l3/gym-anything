#!/bin/bash
echo "=== Exporting splunk_platform_health result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all dashboards
DASHBOARDS_TEMP=$(mktemp /tmp/dashboards.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$DASHBOARDS_TEMP" 2>/dev/null

# Fetch all saved searches
SEARCHES_TEMP=$(mktemp /tmp/searches.XXXXXX.json)
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SEARCHES_TEMP" 2>/dev/null

# Analyze the fetched data using Python
ANALYSIS=$(python3 - "$DASHBOARDS_TEMP" "$SEARCHES_TEMP" << 'PYEOF'
import sys, json, re

try:
    with open(sys.argv[1], 'r') as f:
        dash_data = json.load(f)
except Exception:
    dash_data = {}

try:
    with open(sys.argv[2], 'r') as f:
        search_data = json.load(f)
except Exception:
    search_data = {}

def normalize_name(name):
    return name.lower().replace(' ', '_').replace('-', '_')

# Find the target dashboard
found_dash = {}
expected_dash_norm = "splunk_platform_health"

for entry in dash_data.get('entry', []):
    name = entry.get('name', '')
    label = entry.get('content', {}).get('label', '')
    
    name_norm = normalize_name(name)
    label_norm = normalize_name(label)
    
    if expected_dash_norm in name_norm or expected_dash_norm in label_norm:
        xml_content = entry.get('content', {}).get('eai:data', '')
        # Count panel tags in XML
        panel_count = len(re.findall(r'<panel\b', xml_content, re.IGNORECASE))
        
        found_dash = {
            "name": name,
            "label": label,
            "xml": xml_content,
            "panel_count": panel_count,
            "updated": entry.get('updated', '')
        }
        break

# Find the target saved search
found_search = {}
expected_search_norm = "splunk_indexing_anomaly_detection"

for entry in search_data.get('entry', []):
    name = entry.get('name', '')
    name_norm = normalize_name(name)
    
    if expected_search_norm in name_norm:
        found_search = {
            "name": name,
            "search": entry.get('content', {}).get('search', ''),
            "updated": entry.get('updated', '')
        }
        break

result = {
    "dashboard": found_dash,
    "saved_search": found_search
}

print(json.dumps(result))
PYEOF
)

rm -f "$DASHBOARDS_TEMP" "$SEARCHES_TEMP"

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "analysis": $ANALYSIS,
    "screenshot_path": "/tmp/task_end_screenshot.png",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result safely
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="