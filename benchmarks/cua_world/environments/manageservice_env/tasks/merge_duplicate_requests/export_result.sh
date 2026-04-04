#!/bin/bash
echo "=== Exporting Merge Requests Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load expected IDs
PARENT_ID=""
CHILD_IDS="[]"
if [ -f "/tmp/task_requests.json" ]; then
    PARENT_ID=$(python3 -c "import json; print(json.load(open('/tmp/task_requests.json')).get('parent_id', ''))")
    CHILD_IDS_STR=$(python3 -c "import json; print(','.join(map(str, json.load(open('/tmp/task_requests.json')).get('child_ids', []))))")
fi

echo "Verifying Parent ID: $PARENT_ID"
echo "Verifying Child IDs: $CHILD_IDS_STR"

# Create SQL query to check status and relationships
# Tables: WorkOrder (wo), WorkOrderStates (wos), WorkOrderToWorkOrder (wtwo - for merges)
# Note: In SDP, 'WorkOrderToWorkOrder' usually stores relationships.
# RelationshipID for merge might vary, but we can just check existence of link where PARENT_ID is parent.

# 1. Fetch Request Statuses
# We fetch ID, Title, StatusName, IsParent
# StatusID links to WorkOrderStates. But simplified query:
SQL_STATUS="
SELECT 
    wo.WORKORDERID, 
    wo.TITLE, 
    sdef.STATUSNAME,
    wo.CREATEDTIME,
    wo.COMPLETEDTIME
FROM WorkOrder wo
LEFT JOIN WorkOrderStates wos ON wo.WORKORDERID = wos.WORKORDERID
LEFT JOIN StatusDefinition sdef ON wos.STATUSID = sdef.STATUSID
WHERE wo.WORKORDERID IN ($PARENT_ID, $CHILD_IDS_STR);
"

# 2. Fetch Merge Relationships
# We check if children are linked to parent
SQL_LINKS="
SELECT 
    WORKORDERID, 
    PARENTWORKORDERID
FROM WorkOrderToWorkOrder
WHERE PARENTWORKORDERID = $PARENT_ID
  AND WORKORDERID IN ($CHILD_IDS_STR);
"

echo "Executing Database Checks..."
STATUS_OUTPUT=$(sdp_db_exec "$SQL_STATUS")
LINKS_OUTPUT=$(sdp_db_exec "$SQL_LINKS")

# Save raw output for debugging
echo "$STATUS_OUTPUT" > /tmp/db_status_raw.txt
echo "$LINKS_OUTPUT" > /tmp/db_links_raw.txt

# Python script to parse DB output and create JSON result
cat > /tmp/parse_results.py << PYEOF
import json
import sys
import os

try:
    with open('/tmp/task_requests.json', 'r') as f:
        request_map = json.load(f)
except:
    request_map = {}

parent_id = str(request_map.get('parent_id', ''))
child_ids = [str(x) for x in request_map.get('child_ids', [])]

# Parse status output (pipe separated: ID|TITLE|STATUS|CREATED|COMPLETED)
# Note: sdp_db_exec returns pipe separated values
requests_status = {}
try:
    with open('/tmp/db_status_raw.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('|')
            if len(parts) >= 3:
                wo_id = parts[0].strip()
                requests_status[wo_id] = {
                    "title": parts[1],
                    "status": parts[2]
                }
except Exception as e:
    print(f"Error parsing status: {e}")

# Parse links output (ID|PARENT_ID)
links = []
try:
    with open('/tmp/db_links_raw.txt', 'r') as f:
        for line in f:
            parts = line.strip().split('|')
            if len(parts) >= 2:
                links.append({
                    "child": parts[0].strip(),
                    "parent": parts[1].strip()
                })
except Exception as e:
    print(f"Error parsing links: {e}")

# Construct Result
result = {
    "parent": {
        "id": parent_id,
        "status": requests_status.get(parent_id, {}).get("status", "Unknown"),
        "expected_subject_match": "server" in requests_status.get(parent_id, {}).get("title", "").lower()
    },
    "children": [],
    "links_found": len(links),
    "timestamp_check": True # Placeholder, verified in verifier via task_start logic if needed
}

for cid in child_ids:
    child_stat = requests_status.get(cid, {}).get("status", "Unknown")
    is_linked = any(l["child"] == cid and l["parent"] == parent_id for l in links)
    result["children"].append({
        "id": cid,
        "status": child_stat,
        "is_linked_to_parent": is_linked
    })

print(json.dumps(result, indent=2))
PYEOF

echo "Parsing results..."
python3 /tmp/parse_results.py > /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json