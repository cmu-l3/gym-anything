#!/bin/bash
echo "=== Exporting create_security_app result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query the REST API for the app and its knowledge objects
# Use an inline python script to cleanly interact with the API and handle potential 404s
ANALYSIS=$(python3 - << 'PYEOF'
import json, subprocess

def run_curl(url):
    res = subprocess.run(
        ['curl', '-sk', '-u', 'admin:SplunkAdmin1!', url],
        capture_output=True, text=True
    )
    try:
        return json.loads(res.stdout)
    except:
        return {}

# 1. Check App existence and metadata
app_data = run_curl('https://localhost:8089/services/apps/local/ssh_security_monitor?output_mode=json')
app_exists = False
app_disabled = True
app_label = ""

if "entry" in app_data and len(app_data["entry"]) > 0:
    app_exists = True
    content = app_data["entry"][0].get("content", {})
    app_disabled = content.get("disabled", True)
    app_label = content.get("label", "")

# 2. Check Saved Searches in the app namespace
searches_data = run_curl('https://localhost:8089/servicesNS/-/ssh_security_monitor/saved/searches?output_mode=json&count=0')
saved_searches = []
if "entry" in searches_data:
    for e in searches_data["entry"]:
        # Only collect searches actually belonging to this app (ignores global exports from others)
        acl_app = e.get("acl", {}).get("app", "")
        if acl_app == "ssh_security_monitor":
            saved_searches.append({
                "name": e.get("name", ""),
                "search": e.get("content", {}).get("search", ""),
                "app": acl_app
            })

# 3. Check Dashboards (views) in the app namespace
views_data = run_curl('https://localhost:8089/servicesNS/-/ssh_security_monitor/data/ui/views?output_mode=json&count=0')
dashboards = []
if "entry" in views_data:
    for e in views_data["entry"]:
        acl_app = e.get("acl", {}).get("app", "")
        if acl_app == "ssh_security_monitor":
            dashboards.append({
                "name": e.get("name", ""),
                "xml": e.get("content", {}).get("eai:data", ""),
                "app": acl_app
            })

output = {
    "app": {
        "exists": app_exists,
        "disabled": app_disabled,
        "label": app_label
    },
    "saved_searches": saved_searches,
    "dashboards": dashboards
}
print(json.dumps(output))
PYEOF
)

# Bundle results
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/create_app_result.json

echo "Result saved to /tmp/create_app_result.json"
cat /tmp/create_app_result.json
echo "=== Export complete ==="