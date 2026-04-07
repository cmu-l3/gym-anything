#!/bin/bash
echo "=== Exporting gdpr_ip_anonymization result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

echo "Extracting task artifacts via REST API..."

# 1. Fetch Index configuration
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/services/data/indexes/gdpr_logs?output_mode=json" \
    > /tmp/gdpr_index_info.json 2>/dev/null

# 2. Fetch Props configuration (to check for SEDCMD)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/services/configs/conf-props/apache_gdpr?output_mode=json" \
    > /tmp/gdpr_props_info.json 2>/dev/null

# 3. Fetch Saved Search configuration
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/servicesNS/-/-/saved/searches/Anonymized_Traffic_Report?output_mode=json" \
    > /tmp/gdpr_report_info.json 2>/dev/null

# 4. Fetch Raw Events directly (bypasses UI search-time transformations to check disk payload)
curl -sk -u "admin:SplunkAdmin1!" \
    "https://localhost:8089/services/search/jobs" \
    -d search="search index=gdpr_logs | head 100" \
    -d exec_mode=oneshot \
    -d output_mode=json \
    > /tmp/gdpr_events_info.json 2>/dev/null

# Consolidate everything into a clean JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 - << 'PYEOF'
import json
import sys

def load_json(filepath):
    try:
        with open(filepath, 'r') as f:
            return json.load(f)
    except Exception:
        return {}

index_data = load_json('/tmp/gdpr_index_info.json')
props_data = load_json('/tmp/gdpr_props_info.json')
report_data = load_json('/tmp/gdpr_report_info.json')
events_data = load_json('/tmp/gdpr_events_info.json')

result = {
    "index": index_data,
    "props": props_data,
    "report": report_data,
    "events": events_data
}

with open(sys.argv[1], 'w') as f:
    json.dump(result, f, indent=2)
PYEOF \
    "$TEMP_JSON"

# Safely place the result file for the host to access
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Result JSON written."
echo "=== Export complete ==="