#!/bin/bash
echo "=== Exporting index_lifecycle_management result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Query index data via REST API
echo "Querying index states..."
curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/data/indexes/audit_trail?output_mode=json > /tmp/audit_trail.json 2>/dev/null || echo "{}" > /tmp/audit_trail.json
curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/data/indexes/security_logs?output_mode=json > /tmp/security_logs.json 2>/dev/null || echo "{}" > /tmp/security_logs.json
curl -sk -u admin:SplunkAdmin1! https://localhost:8089/services/data/indexes/web_logs?output_mode=json > /tmp/web_logs.json 2>/dev/null || echo "{}" > /tmp/web_logs.json

# Query saved search data via REST API
# Using normalized name for case sensitivity issues
echo "Querying saved search state..."
curl -sk -u admin:SplunkAdmin1! https://localhost:8089/servicesNS/-/-/saved/searches/Index_Volume_Monitor?output_mode=json > /tmp/saved_search.json 2>/dev/null || echo "{}" > /tmp/saved_search.json

# If not found under exact case, try fetching all and matching
if ! grep -q "Index_Volume_Monitor" /tmp/saved_search.json 2>/dev/null; then
    curl -sk -u admin:SplunkAdmin1! https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json > /tmp/all_searches.json 2>/dev/null || echo "{}" > /tmp/all_searches.json
fi

ANALYSIS=$(python3 - << 'PYEOF'
import json, sys

def get_index_info(file_path):
    try:
        with open(file_path, 'r') as f:
            data = json.load(f)
            entries = data.get('entry', [])
            if entries:
                content = entries[0].get('content', {})
                return {
                    "exists": True,
                    "frozenTimePeriodInSecs": content.get("frozenTimePeriodInSecs", ""),
                    "maxTotalDataSizeMB": content.get("maxTotalDataSizeMB", "")
                }
    except Exception as e:
        pass
    return {"exists": False, "frozenTimePeriodInSecs": "", "maxTotalDataSizeMB": ""}

def get_search_info(exact_path, all_path):
    # Try exact match first
    try:
        with open(exact_path, 'r') as f:
            data = json.load(f)
            entries = data.get('entry', [])
            if entries:
                content = entries[0].get('content', {})
                return {
                    "exists": True,
                    "search": content.get("search", "")
                }
    except:
        pass
    
    # Try searching through all if exact failed
    try:
        with open(all_path, 'r') as f:
            data = json.load(f)
            entries = data.get('entry', [])
            for entry in entries:
                if entry.get('name', '').lower() == 'index_volume_monitor':
                    content = entry.get('content', {})
                    return {
                        "exists": True,
                        "search": content.get("search", "")
                    }
    except:
        pass
    
    return {"exists": False, "search": ""}

result = {
    "audit_trail": get_index_info('/tmp/audit_trail.json'),
    "security_logs": get_index_info('/tmp/security_logs.json'),
    "web_logs": get_index_info('/tmp/web_logs.json'),
    "saved_search": get_search_info('/tmp/saved_search.json', '/tmp/all_searches.json')
}
print(json.dumps(result))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/index_lifecycle_result.json

echo "Result saved to /tmp/index_lifecycle_result.json"
cat /tmp/index_lifecycle_result.json
echo "=== Export complete ==="