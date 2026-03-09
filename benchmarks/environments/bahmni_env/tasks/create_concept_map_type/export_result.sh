#!/bin/bash
# Export script for create_concept_map_type task
# Queries OpenMRS API and exports state to JSON

set -e

# Source utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting create_concept_map_type result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query OpenMRS API for all concept map types (full view to get descriptions/audit info)
echo "Querying OpenMRS API..."
API_RESPONSE=$(openmrs_api_get "/conceptmaptype?v=full&limit=100" 2>/dev/null || echo "{}")

# Process result with Python to handle JSON robustly and safely
# We create a JSON object containing all verification signals
EXPORT_JSON=$(python3 << PYEOF
import json
import sys
import datetime

# Helper to parse dates like "2025-01-01T12:00:00.000+0000"
def parse_openmrs_date(date_str):
    if not date_str: return 0
    try:
        # Remove timezone for simplicity or handle if needed
        dt_str = date_str.split('.')[0] 
        dt = datetime.datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%S")
        return int(dt.timestamp())
    except:
        return 0

try:
    api_data = json.loads('''$API_RESPONSE''')
    results = api_data.get('results', [])
except Exception as e:
    results = []

# Find the target map type
target = None
for r in results:
    if r.get('name', '') == 'ASSOCIATED-WITH':
        target = r
        break

# If not found exactly, look for case-insensitive match
if not target:
    for r in results:
        if r.get('name', '').upper() == 'ASSOCIATED-WITH':
            target = r
            break

output = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": int("$INITIAL_COUNT"),
    "current_count": len(results),
    "found": False,
    "map_type": {}
}

if target:
    audit = target.get('auditInfo', {})
    date_created_ts = parse_openmrs_date(audit.get('dateCreated', ''))
    
    output["found"] = True
    output["map_type"] = {
        "uuid": target.get('uuid'),
        "name": target.get('name'),
        "description": target.get('description', ''),
        "retired": target.get('retired', False),
        "isHidden": target.get('isHidden', False),
        "date_created_ts": date_created_ts
    }

print(json.dumps(output, indent=2))
PYEOF
)

# Save result to file
echo "$EXPORT_JSON" > /tmp/task_result.json

# Log for debugging
echo "Exported Data:"
cat /tmp/task_result.json

echo "=== Export complete ==="