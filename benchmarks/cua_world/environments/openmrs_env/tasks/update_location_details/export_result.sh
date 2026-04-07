#!/bin/bash
# Export: update_location_details task
# Queries the database for the current state of the 'Laboratory' location.

set -e
echo "=== Exporting update_location_details results ==="
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# ── Query Database ───────────────────────────────────────────────────────────
# We select description and modification time for the Laboratory
# We use Python to format the SQL result into JSON safely

echo "Querying OpenMRS database..."

# DB Query: Get description and last changed date (unix timestamp)
# Note: UNIX_TIMESTAMP(date_changed) handles time zone conversion usually, 
# assuming DB is in system time. If date_changed is null, check date_created.
SQL="SELECT description, COALESCE(UNIX_TIMESTAMP(date_changed), UNIX_TIMESTAMP(date_created)) as last_mod FROM location WHERE name = 'Laboratory' AND retired = 0 LIMIT 1;"

# Execute query using the helper function
# The helper typically returns raw text, tab separated
DB_RESULT=$(omrs_db_query "$SQL")

# Parse DB result using Python to create a structured JSON
# Handles potential empty results or special characters in description
python3 -c "
import json
import sys
import time

try:
    raw_result = '''$DB_RESULT'''
    task_start = int('$TASK_START')
    task_end = int('$TASK_END')
    
    data = {
        'location_found': False,
        'current_description': '',
        'last_modified_ts': 0,
        'modified_during_task': False,
        'task_start': task_start,
        'task_end': task_end
    }

    if raw_result and raw_result.strip():
        # raw_result likely 'Description Text\t1234567890'
        # Split from right to handle spaces in description safely
        parts = raw_result.strip().rsplit('\t', 1)
        if len(parts) == 2:
            desc = parts[0]
            ts = int(parts[1]) if parts[1].isdigit() else 0
            
            data['location_found'] = True
            data['current_description'] = desc
            data['last_modified_ts'] = ts
            
            # Anti-gaming check: was it modified after task start?
            # We add a small buffer (e.g., -5 seconds) to account for slight clock skews
            if ts >= (task_start - 5):
                data['modified_during_task'] = True

    # Save to file
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
        
except Exception as e:
    print(f'Error processing export: {e}', file=sys.stderr)
    sys.exit(1)
"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="