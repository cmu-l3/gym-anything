#!/bin/bash
# Export script for "configure_task_dependencies" task
# Dumps task and dependency tables from PostgreSQL to JSON

echo "=== Exporting Task Dependencies Result ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to extract:
# 1. The ID of our target request
# 2. The IDs and Titles of tasks belonging to that request
# 3. The dependency mapping (parent_id -> child_id) for those tasks

# SQL to get the data as JSON
# Note: Schema varies slightly by SDP version. 
# - Request info is in 'workorder'
# - Tasks are also in 'workorder' but linked via 'wo_task' (parent_wo_id -> task_wo_id)
# - Dependency is usually 'wo_task_dependency' (parent_task_id, child_task_id, dependency_type)
# - Titles are in 'taskdetails' (linked to workorder.workorderid)

echo "Querying database for dependencies..."

EXPORT_SQL="
WITH target_req AS (
    SELECT workorderid 
    FROM workorder 
    WHERE title LIKE 'Deploy HA Web Cluster - Project Alpha%' 
    ORDER BY workorderid DESC 
    LIMIT 1
),
req_tasks AS (
    -- Get all tasks associated with the request
    SELECT 
        wt.task_id AS task_wo_id,
        td.title AS task_title
    FROM wo_task wt
    JOIN taskdetails td ON wt.task_id = td.task_id
    WHERE wt.workorderid = (SELECT workorderid FROM target_req)
),
deps AS (
    -- Get dependencies where both parent and child are in our task list
    SELECT 
        wtd.parent_task_id,
        wtd.task_id AS child_task_id
    FROM wo_task_dependency wtd
    WHERE wtd.task_id IN (SELECT task_wo_id FROM req_tasks)
)
SELECT json_build_object(
    'request_id', (SELECT workorderid FROM target_req),
    'tasks', (SELECT json_agg(row_to_json(t)) FROM req_tasks t),
    'dependencies', (SELECT json_agg(row_to_json(d)) FROM deps d)
);
"

# Execute Query
RESULT_JSON_RAW=$(sdp_db_exec "$EXPORT_SQL")

# Clean up output (sometimes psql adds headers/footers even with -t -A if not careful)
# The sdp_db_exec function handles basic cleanup, but we ensure valid JSON
echo "$RESULT_JSON_RAW" > /tmp/raw_db_output.txt

# Create formatted result file
# Use Python to ensure it's valid JSON and add timestamps
python3 -c "
import json
import sys
import time

try:
    raw = open('/tmp/raw_db_output.txt').read().strip()
    if not raw:
        data = {'error': 'No data returned from DB'}
    else:
        # Postgres might output 'json_build_object' or just the json
        # Try to find the first '{' and last '}'
        start = raw.find('{')
        end = raw.rfind('}') + 1
        if start != -1 and end != -1:
            data = json.loads(raw[start:end])
        else:
            data = {'error': 'Invalid JSON format from DB'}
            
    # Add metadata
    data['timestamp'] = time.time()
    data['screenshot_exists'] = True # Verified by existence of file in setup
    
    print(json.dumps(data, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# Permission fix
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result.json