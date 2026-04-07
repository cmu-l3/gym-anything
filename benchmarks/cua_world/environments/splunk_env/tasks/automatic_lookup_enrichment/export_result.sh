#!/bin/bash
echo "=== Exporting automatic_lookup_enrichment result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Fetch current lookup definitions to check for http_status_def
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/data/transforms/lookups/http_status_def?output_mode=json" \
    > /tmp/current_lookup_def.json 2>/dev/null

# 2. Fetch current saved searches to check for Web_Status_Summary
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/servicesNS/-/-/saved/searches?output_mode=json&count=0" \
    > /tmp/current_saved_searches.json 2>/dev/null

# 3. FUNCTIONAL TEST: Run a search to see if the automatic lookup actually enriches the data
# We search for events that have the status_description field populated.
curl -sk -u "${SPLUNK_USER}:${SPLUNK_PASS}" \
    "${SPLUNK_API}/services/search/jobs" \
    -d "search=search index=tutorial sourcetype=access_combined* | head 5000 | stats count by status_description | search status_description=\"*\"" \
    -d "exec_mode=oneshot" \
    -d "output_mode=json" \
    > /tmp/functional_test.json 2>/dev/null

# 4. Use Python to process all the API outputs and produce a clean JSON result
python3 - << 'PYEOF' > /tmp/task_result.json
import json
import sys

result = {
    "lookup_def_exists": False,
    "saved_search_exists": False,
    "saved_search_query": "",
    "functional_enriched_count": 0,
    "functional_distinct_descriptions": 0
}

# Process Lookup Definition
try:
    with open('/tmp/current_lookup_def.json', 'r') as f:
        lookup_data = json.load(f)
        if 'entry' in lookup_data and len(lookup_data['entry']) > 0:
            result['lookup_def_exists'] = True
except Exception as e:
    pass

# Process Saved Searches
try:
    with open('/tmp/current_saved_searches.json', 'r') as f:
        searches_data = json.load(f)
        for entry in searches_data.get('entry', []):
            if entry.get('name') == 'Web_Status_Summary':
                result['saved_search_exists'] = True
                result['saved_search_query'] = entry.get('content', {}).get('search', '')
                break
except Exception as e:
    pass

# Process Functional Test
try:
    with open('/tmp/functional_test.json', 'r') as f:
        func_data = json.load(f)
        search_results = func_data.get('results', [])
        
        enriched_count = 0
        distinct_descriptions = 0
        
        for row in search_results:
            desc = row.get('status_description', '')
            count = int(row.get('count', '0'))
            if desc and str(desc).strip():
                enriched_count += count
                distinct_descriptions += 1
                
        result['functional_enriched_count'] = enriched_count
        result['functional_distinct_descriptions'] = distinct_descriptions
except Exception as e:
    pass

print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/task_result.json
echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="