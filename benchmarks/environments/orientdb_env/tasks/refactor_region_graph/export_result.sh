#!/bin/bash
echo "=== Exporting Refactor Region Graph Result ==="

source /workspace/scripts/task_utils.sh

# Record timestamp
date +%s > /tmp/task_end_time.txt

# Take final screenshot
take_screenshot /tmp/task_final.png

# === EXTRACT DATABASE STATE ===
# We will run several queries to introspect the schema and data structure
# and save the results to a JSON file for the verifier.

# 1. Check Schema (Classes)
SCHEMA_JSON=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb")

# 2. Count Regions
REGION_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM Regions" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 3. List Unique Region Names
REGION_NAMES_JSON=$(orientdb_sql "demodb" "SELECT Name FROM Regions")

# 4. Count InRegion Edges
EDGE_COUNT=$(orientdb_sql "demodb" "SELECT COUNT(*) as cnt FROM InRegion" 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0")

# 5. Sample Connections (Country -> Region)
# We want to verify that Italy -> European, US -> American, etc.
# Query: Select the country name and the connected region name
CONNECTIONS_JSON=$(orientdb_sql "demodb" "SELECT out.Name as Country, in.Name as Region FROM InRegion")

# 6. Check Indexes on Regions
# This information is inside SCHEMA_JSON, so we'll parse it in Python later, 
# or we can try to extract it specifically if needed.

# Construct the result JSON
# We use Python to robustly construct the JSON object from the various API responses
python3 -c "
import json
import sys

try:
    schema = json.loads('''${SCHEMA_JSON}''')
    region_names_res = json.loads('''${REGION_NAMES_JSON}''')
    connections_res = json.loads('''${CONNECTIONS_JSON}''')
    
    # Extract just the names list
    region_names = [r.get('Name') for r in region_names_res.get('result', []) if r.get('Name')]
    
    # Extract connections list
    connections = [{
        'Country': c.get('Country'),
        'Region': c.get('Region')
    } for c in connections_res.get('result', [])]

    result = {
        'schema': schema,
        'region_count': int('${REGION_COUNT}'),
        'region_names': region_names,
        'edge_count': int('${EDGE_COUNT}'),
        'connections': connections,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > /tmp/task_result.json

# Adjust permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json