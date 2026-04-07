#!/bin/bash
# Export script for manage_versioned_publications
# Collects state of Source Doc, Public Proxy, and Internal Proxy

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper to get document JSON by path
get_doc_json() {
    curl -s -u "$NUXEO_AUTH" \
        -H "X-NXproperties: *" \
        "$NUXEO_URL/api/v1/path$1"
}

# 1. Get Source Document State
echo "Fetching Source Document..."
SOURCE_JSON=$(get_doc_json "/default-domain/workspaces/Projects/Titanium-X-Specs")

# 2. Get Public Proxy State (Customer Portal)
# Note: The name of the proxy might be the same as the source 'Titanium-X-Specs'
echo "Fetching Public Proxy..."
PUBLIC_PROXY_JSON=$(get_doc_json "/default-domain/sections/Customer-Portal/Titanium-X-Specs")

# 3. Get Internal Proxy State (Engineering Internal)
echo "Fetching Internal Proxy..."
INTERNAL_PROXY_JSON=$(get_doc_json "/default-domain/sections/Engineering-Internal/Titanium-X-Specs")

# 4. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 5. Compile Result JSON
# We use a Python script to parse the Nuxeo JSONs and construct the result object
# safely handling missing docs/properties.

python3 -c "
import json
import os
import sys

def safe_load(json_str):
    try:
        return json.loads(json_str)
    except:
        return {}

source = safe_load('''$SOURCE_JSON''')
public = safe_load('''$PUBLIC_PROXY_JSON''')
internal = safe_load('''$INTERNAL_PROXY_JSON''')

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'source': {
        'exists': 'uid' in source,
        'uid': source.get('uid'),
        'versionLabel': source.get('properties', {}).get('uid:major_version', 0) if source.get('properties') else '0.0',
        'digest': source.get('properties', {}).get('file:content', {}).get('digest')
    },
    'public_proxy': {
        'exists': 'uid' in public,
        'uid': public.get('uid'),
        'isVersion': public.get('isVersion', False),
        'versionLabel': public.get('versionLabel', '0.0'),
        'digest': public.get('properties', {}).get('file:content', {}).get('digest')
    },
    'internal_proxy': {
        'exists': 'uid' in internal,
        'uid': internal.get('uid'),
        'isVersion': internal.get('isVersion', False),
        'versionLabel': internal.get('versionLabel', '0.0'),
        'digest': internal.get('properties', {}).get('file:content', {}).get('digest')
    },
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="