#!/bin/bash
echo "=== Exporting kv_store_blocklist result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Retrieve KV Store Collection Config
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/nobody/search/storage/collections/config/ip_blocklist?output_mode=json" > /tmp/kv_config.json 2>/dev/null

# Retrieve Lookup Definition
# Agent could have created it in either nobody or admin namespace
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/nobody/search/data/transforms/lookups/ip_blocklist_lookup?output_mode=json" > /tmp/kv_lookup.json 2>/dev/null
if ! grep -q "entry" /tmp/kv_lookup.json; then
    curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/admin/search/data/transforms/lookups/ip_blocklist_lookup?output_mode=json" > /tmp/kv_lookup.json 2>/dev/null
fi

# Retrieve KV Store Data
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/nobody/search/storage/collections/data/ip_blocklist?output_mode=json" > /tmp/kv_data.json 2>/dev/null

# Retrieve Saved Searches
curl -sk -u admin:SplunkAdmin1! "https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0" > /tmp/saved_searches.json 2>/dev/null

# Python script to analyze the exported JSON files
ANALYSIS=$(python3 - << 'PYEOF'
import sys, json

# Parse Configuration
try:
    with open('/tmp/kv_config.json') as f:
        kv_config = json.load(f)
except:
    kv_config = {}

# Parse Lookup Definition
try:
    with open('/tmp/kv_lookup.json') as f:
        kv_lookup = json.load(f)
except:
    kv_lookup = {}

# Parse Data
try:
    with open('/tmp/kv_data.json') as f:
        kv_data = json.load(f)
except:
    kv_data = []

# Parse Saved Searches
try:
    with open('/tmp/saved_searches.json') as f:
        saved_searches = json.load(f)
except:
    saved_searches = {}

# 1. Analyze KV Config
collection_exists = False
collection_fields = []
if kv_config.get('entry'):
    collection_exists = True
    content = kv_config['entry'][0].get('content', {})
    for k, v in content.items():
        if k.startswith('field.'):
            collection_fields.append(k.replace('field.', ''))

# 2. Analyze Lookup Definition
lookup_exists = False
lookup_is_kvstore = False
lookup_collection = ""
if kv_lookup.get('entry'):
    lookup_exists = True
    content = kv_lookup['entry'][0].get('content', {})
    lookup_is_kvstore = (content.get('external_type') == 'kvstore')
    lookup_collection = content.get('collection', '')

# 3. Analyze Data
data_entries = []
if isinstance(kv_data, list):
    data_entries = kv_data
elif isinstance(kv_data, dict) and kv_data.get('entry'):
    data_entries = kv_data.get('entry', [])

# 4. Analyze Saved Searches
saved_search_found = False
saved_search_query = ""
for entry in saved_searches.get('entry', []):
    name = entry.get('name', '')
    if name.lower() == 'blocklist_alert':
        saved_search_found = True
        saved_search_query = entry.get('content', {}).get('search', '')
        break

output = {
    "collection_exists": collection_exists,
    "collection_fields": collection_fields,
    "lookup_exists": lookup_exists,
    "lookup_is_kvstore": lookup_is_kvstore,
    "lookup_collection": lookup_collection,
    "data_entries": data_entries,
    "saved_search_found": saved_search_found,
    "saved_search_query": saved_search_query
}
print(json.dumps(output))
PYEOF
)

# Package analysis into final result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="