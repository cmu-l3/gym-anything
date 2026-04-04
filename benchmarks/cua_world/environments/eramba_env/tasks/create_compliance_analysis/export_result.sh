#!/bin/bash
echo "=== Exporting create_compliance_analysis results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_count.txt 2>/dev/null || echo "0")

# 3. Query Database for New Record
# We join compliance_analyses with compliance_package_items to get the linked requirement title
# We filter by creation time > task start time
echo "Querying database for new compliance analysis..."

# Create a temporary SQL script to handle the export safely
cat > /tmp/export_query.sql << SQL_EOF
SELECT 
    JSON_OBJECT(
        'id', ca.id,
        'item_title', cpi.title,
        'item_id', cpi.item_id,
        'analysis_text', ca.analysis,
        'status_id', ca.analysis_status_id,
        'created_at', ca.created,
        'modified_at', ca.modified
    )
FROM compliance_analyses ca
JOIN compliance_package_items cpi ON ca.compliance_package_item_id = cpi.id
WHERE ca.created >= FROM_UNIXTIME($TASK_START)
ORDER BY ca.id DESC LIMIT 1;
SQL_EOF

# Execute query and capture JSON output
DB_RESULT=$(docker exec -i eramba-db mysql -u eramba -peramba_db_pass eramba -N < /tmp/export_query.sql 2>/dev/null)

# Get final count
FINAL_COUNT=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e "SELECT COUNT(*) FROM compliance_analyses;" 2>/dev/null || echo "0")

# 4. Construct Result JSON
# Use python to construct robust JSON
python3 -c "
import json
import sys
import time

try:
    db_record_str = '''$DB_RESULT'''
    db_record = json.loads(db_record_str) if db_record_str.strip() else None
    
    result = {
        'task_start': $TASK_START,
        'initial_count': int('$INITIAL_COUNT'),
        'final_count': int('$FINAL_COUNT'),
        'record_found': db_record is not None,
        'record': db_record,
        'timestamp': time.time(),
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(result, indent=2))
except Exception as e:
    print(json.dumps({'error': str(e)}))
" > /tmp/task_result.json

# Cleanup
rm -f /tmp/export_query.sql

# Output for logging
echo "Exported Result:"
cat /tmp/task_result.json
echo "=== Export complete ==="