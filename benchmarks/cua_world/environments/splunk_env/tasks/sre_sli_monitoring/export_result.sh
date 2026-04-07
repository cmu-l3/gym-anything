#!/bin/bash
echo "=== Exporting sre_sli_monitoring result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Fetch all saved searches
curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0" > /tmp/all_searches.json 2>/dev/null

# Fetch all dashboards
curl -sk -u "admin:SplunkAdmin1!" "https://localhost:8089/servicesNS/-/-/data/ui/views?output_mode=json&count=0" > /tmp/all_dashboards.json 2>/dev/null

# Process data
python3 - << 'PYEOF'
import json

alert_data = {'found': False}
dash_data = {'found': False}

try:
    with open('/tmp/all_searches.json', 'r') as f:
        searches = json.load(f).get('entry', [])
        for s in searches:
            name = s.get('name', '')
            if name.lower().replace(' ', '_') == 'high_error_rate_alert':
                content = s.get('content', {})
                alert_data = {
                    'found': True,
                    'name': name,
                    'search': content.get('search', ''),
                    'cron_schedule': content.get('cron_schedule', ''),
                    'is_scheduled': content.get('is_scheduled', 0)
                }
                break
except Exception as e:
    alert_data['error'] = str(e)

try:
    with open('/tmp/all_dashboards.json', 'r') as f:
        dashboards = json.load(f).get('entry', [])
        for d in dashboards:
            name = d.get('name', '')
            content = d.get('content', {})
            label = content.get('label', '')
            
            norm_name = name.lower().replace(' ', '_')
            norm_label = label.lower().replace(' ', '_')
            
            if 'service_level_indicators' in norm_name or 'service_level_indicators' in norm_label:
                dash_data = {
                    'found': True,
                    'name': name,
                    'label': label,
                    'xml': content.get('eai:data', '')
                }
                break
except Exception as e:
    dash_data['error'] = str(e)

out = {'alert': alert_data, 'dashboard': dash_data}
with open('/tmp/sre_sli_result.json', 'w') as f:
    json.dump(out, f)
PYEOF

# Fix permissions
chmod 666 /tmp/sre_sli_result.json 2>/dev/null || true

echo "Result saved to /tmp/sre_sli_result.json"
cat /tmp/sre_sli_result.json
echo -e "\n=== Export complete ==="