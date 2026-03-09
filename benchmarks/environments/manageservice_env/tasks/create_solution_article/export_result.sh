#!/bin/bash
# Export script for create_solution_article task
# Queries the SDP database for the created solution and exports results

echo "=== Exporting Create Solution Article results ==="
source /workspace/scripts/task_utils.sh

# 1. Capture final state screenshot
take_screenshot /tmp/task_final.png

# 2. Get task timing
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_solution_count.txt 2>/dev/null || echo "0")

# 3. Query the database for the solution
# We look for the specific title requested in the task
TARGET_TITLE="VPN Connection Drops After Windows 11 Update KB5034441"

echo "Querying database for solution: $TARGET_TITLE"

# We fetch relevant columns: Title, Description (might be in separate table or column), Status, Keywords
# SDP Schema varies by version, but 'Solution' usually contains the core info.
# We'll fetch the most recent solution to be safe.
LATEST_SOLUTION=$(sdp_db_exec "SELECT title, description, status_id, solution_id, createdtime FROM Solution ORDER BY createdtime DESC LIMIT 1;" 2>/dev/null)

# Also check specifically for our title to be robust against other random creations
SPECIFIC_SOLUTION=$(sdp_db_exec "SELECT title, description, status_id, solution_id, createdtime FROM Solution WHERE title LIKE '%VPN Connection Drops%' LIMIT 1;" 2>/dev/null)

# Determine which record to use (prefer specific match)
if [ -n "$SPECIFIC_SOLUTION" ]; then
    RECORD="$SPECIFIC_SOLUTION"
    echo "Found specific match."
else
    RECORD="$LATEST_SOLUTION"
    echo "No specific match found, checking latest record."
fi

# Get current count
CURRENT_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM Solution;" 2>/dev/null || echo "0")

# 4. Extract Keywords
# Keywords are often in a separate table or column (Solution_Keywords or similar).
# We'll try to fetch them if we have a solution ID.
SOLUTION_ID=$(echo "$RECORD" | cut -d'|' -f4 2>/dev/null)
KEYWORDS=""
if [ -n "$SOLUTION_ID" ]; then
    # Try generic tag/keyword table pattern
    KEYWORDS=$(sdp_db_exec "SELECT keyword FROM SolutionKeyword WHERE solution_id = $SOLUTION_ID;" 2>/dev/null || echo "")
fi

# 5. Check "Published" status
# We need to map status_id to name. Usually in 'SolutionStatus' table.
STATUS_ID=$(echo "$RECORD" | cut -d'|' -f3 2>/dev/null)
STATUS_NAME=""
if [ -n "$STATUS_ID" ]; then
    STATUS_NAME=$(sdp_db_exec "SELECT name FROM SolutionStatus WHERE status_id = $STATUS_ID;" 2>/dev/null || echo "Unknown")
fi

# 6. Create JSON result
# We use Python to safely construct the JSON to avoid shell escaping issues with the description content
python3 -c "
import json
import sys
import time

try:
    record = '''$RECORD'''
    keywords = '''$KEYWORDS'''
    status_name = '''$STATUS_NAME'''
    initial_count = int('''$INITIAL_COUNT''' or 0)
    current_count = int('''$CURRENT_COUNT''' or 0)
    task_start = int('''$TASK_START''' or 0)
    
    parts = record.split('|')
    data = {}
    
    if len(parts) >= 5:
        data['found'] = True
        data['title'] = parts[0].strip()
        data['description'] = parts[1].strip()
        data['status_id'] = parts[2].strip()
        data['id'] = parts[3].strip()
        # createdtime is usually in milliseconds in SDP
        try:
            created_ts = int(parts[4].strip()) / 1000
            data['created_timestamp'] = created_ts
            data['created_during_task'] = created_ts > task_start
        except:
            data['created_timestamp'] = 0
            data['created_during_task'] = False
    else:
        data['found'] = False
        data['created_during_task'] = (current_count > initial_count)

    data['status_name'] = status_name.strip()
    data['keywords'] = keywords.strip().split('\n')
    data['initial_count'] = initial_count
    data['current_count'] = current_count
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)

except Exception as e:
    print(f'Error creating JSON: {e}')
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'found': False, 'error': str(e)}, f)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="