#!/bin/bash
echo "=== Exporting linux_pam_execution_audit result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve current Splunk knowledge objects
DASHBOARDS_TEMP=$(mktemp /tmp/dashboards.XXXXXX.json)
SEARCHES_TEMP=$(mktemp /tmp/searches.XXXXXX.json)

curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/ui/views?output_mode=json&count=0" \
    > "$DASHBOARDS_TEMP" 2>/dev/null

curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > "$SEARCHES_TEMP" 2>/dev/null

# Parse the JSON and extract specifics for our required objects
ANALYSIS=$(python3 - "$DASHBOARDS_TEMP" "$SEARCHES_TEMP" << 'PYEOF'
import sys, json, re

dash_file = sys.argv[1]
search_file = sys.argv[2]

try:
    with open(dash_file, 'r') as f:
        dash_data = json.load(f)
        
    with open(search_file, 'r') as f:
        search_data = json.load(f)

    # Find the requested dashboard
    dashboard = None
    for d in dash_data.get('entry', []):
        if d.get('name', '').lower() == 'privileged_execution_audit':
            dashboard = d
            break
            
    # Find the requested alert
    alert = None
    for s in search_data.get('entry', []):
        if s.get('name', '').lower() == 'failed_privileged_escalation':
            alert = s
            break

    # Analyze Dashboard
    dash_info = {"exists": False}
    if dashboard:
        xml = dashboard.get('content', {}).get('eai:data', '')
        panel_count = len(re.findall(r'<panel\b', xml, re.IGNORECASE)) if xml else 0
        has_rex = bool(re.search(r'\b(rex|regex)\b', xml, re.IGNORECASE)) if xml else False
        dash_info = {
            "exists": True,
            "panel_count": panel_count,
            "has_rex": has_rex,
            "xml_preview": xml[:500] if xml else ""
        }
        
    # Analyze Alert
    alert_info = {"exists": False}
    if alert:
        content = alert.get('content', {})
        search_str = content.get('search', '')
        is_scheduled = content.get('is_scheduled', 0) in [1, '1', True]
        cron = content.get('cron_schedule', '')
        alert_info = {
            "exists": True,
            "search": search_str,
            "is_scheduled": is_scheduled,
            "cron": cron
        }

    output = {
        "dashboard": dash_info,
        "alert": alert_info
    }
    print(json.dumps(output))

except Exception as e:
    print(json.dumps({"error": str(e), "dashboard": {"exists": False}, "alert": {"exists": False}}))
PYEOF
)

rm -f "$DASHBOARDS_TEMP" "$SEARCHES_TEMP"

# Create final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/linux_pam_execution_audit_result.json

echo "Result saved to /tmp/linux_pam_execution_audit_result.json"
cat /tmp/linux_pam_execution_audit_result.json
echo "=== Export complete ==="