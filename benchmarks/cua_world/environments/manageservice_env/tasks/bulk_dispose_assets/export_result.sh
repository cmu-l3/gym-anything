#!/bin/bash
echo "=== Exporting Bulk Dispose Assets Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query Database for Asset Status
# We need to join resources and resourcestate tables
# Schema: resources.resourcestateid -> resourcestate.resourcestateid
echo "Querying final asset states..."

# We query for name and status name
# We assume 'resourcename' and 'displaystate' columns based on standard SDP schema
# If 'displaystate' doesn't exist, try 'statename'
SQL_QUERY="SELECT r.resourcename, s.displaystate FROM resources r JOIN resourcestate s ON r.resourcestateid = s.resourcestateid WHERE r.resourcename LIKE 'OLD-PC-%' ORDER BY r.resourcename;"

# Execute query using helper
# Output format: Name|Status per line
DB_RESULT=$(sdp_db_exec "$SQL_QUERY" "servicedesk")

echo "Raw DB Result:"
echo "$DB_RESULT"

# 3. Parse results into JSON
# We'll use python to format the DB output into a clean JSON object
cat > /tmp/parse_results.py << PYEOF
import json
import sys
import time

raw_data = """$DB_RESULT"""
target_assets = ["OLD-PC-01", "OLD-PC-02", "OLD-PC-03", "OLD-PC-04", "OLD-PC-05"]
results = {}

lines = raw_data.strip().split('\n')
for line in lines:
    if '|' in line:
        name, status = line.split('|', 1)
        results[name.strip()] = status.strip()

# Build final structure
output = {
    "timestamp": time.time(),
    "assets_found": len(results),
    "asset_states": results,
    "disposed_count": sum(1 for s in results.values() if s.lower() == "disposed"),
    "targets_correct": all(results.get(t, "").lower() == "disposed" for t in target_assets),
    "missing_targets": [t for t in target_assets if t not in results]
}

print(json.dumps(output, indent=2))
PYEOF

# Run parser and save to temp file
python3 /tmp/parse_results.py > /tmp/parsed_result.json 2>/dev/null

# 4. Safely move to final location (handle permissions)
cp /tmp/parsed_result.json /tmp/task_result.json 2>/dev/null || \
    sudo cp /tmp/parsed_result.json /tmp/task_result.json 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported data:"
cat /tmp/task_result.json

echo "=== Export complete ==="