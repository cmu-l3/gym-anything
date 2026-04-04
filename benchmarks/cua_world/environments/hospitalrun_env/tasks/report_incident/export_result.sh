#!/bin/bash
echo "=== Exporting report_incident results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Collect Task Timing Data
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_incident_count.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)

# 3. Query CouchDB for all Incident documents
# We export ALL incident documents found. The verifier will filter for the one created during the task.
# HospitalRun incidents usually have type="incident" inside the "data" object or at root.
echo "Querying CouchDB for incidents..."

# This python script fetches all docs, filters for type='incident' (or id starts with incident_),
# and outputs a JSON list of detailed objects.
python3 -c "
import sys, json, urllib.request

couch_url = '${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/_all_docs?include_docs=true'
try:
    with urllib.request.urlopen(couch_url) as f:
        data = json.loads(f.read().decode('utf-8'))
        
    incidents = []
    for row in data.get('rows', []):
        doc = row.get('doc', {})
        # HospitalRun structure: usually doc['data']['type'] == 'incident'
        # But sometimes just doc['type'] == 'incident'
        # Or ID starts with 'incident_'
        
        doc_data = doc.get('data', doc)
        doc_type = doc_data.get('type', doc.get('type', ''))
        doc_id = doc.get('_id', '')
        
        if doc_type == 'incident' or doc_id.startswith('incident_'):
            # Add metadata for verifier
            doc['_export_timestamp'] = $CURRENT_TIME
            incidents.append(doc)
            
    print(json.dumps({
        'initial_count': int('$INITIAL_COUNT'),
        'task_start_time': int('$TASK_START_TIME'),
        'incidents': incidents
    }, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e), 'incidents': []}))
" > /tmp/task_result.json

# 4. Check if file was successfully created
if [ -s /tmp/task_result.json ]; then
    echo "Export successful. Found $(grep -o "\"_id\"" /tmp/task_result.json | wc -l) total incidents."
else
    echo "Error: Failed to export JSON."
    echo "{}" > /tmp/task_result.json
fi

# 5. Set permissions for copy_from_env
chmod 666 /tmp/task_result.json