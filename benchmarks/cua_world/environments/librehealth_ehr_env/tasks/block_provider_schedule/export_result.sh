#!/bin/bash
echo "=== Exporting Block Provider Schedule Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the database for events created today with relevant titles
# We select key fields to verify the task
echo "Querying calendar events..."

# Create a temporary SQL script to handle the query
cat > /tmp/query_events.sql << SQL
SELECT 
    pc_eid, 
    pc_title, 
    pc_eventDate, 
    pc_startTime, 
    pc_duration, 
    pc_pid,
    pc_aid
FROM openemr_postcalendar_events 
WHERE pc_eventDate = CURDATE() 
  AND (pc_title LIKE '%Staff Meeting%' OR pc_startTime LIKE '16:%');
SQL

# Execute query and format as JSON manually (mysql -e output is tab separated)
# Using python to parse the tab-separated output into JSON for reliability
python3 -c "
import subprocess
import json
import sys

def get_events():
    cmd = ['docker', 'exec', 'librehealth-db', 'mysql', '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', 'SELECT pc_eid, pc_title, pc_eventDate, pc_startTime, pc_duration, pc_pid, pc_aid FROM openemr_postcalendar_events WHERE pc_eventDate = CURDATE()']
    try:
        output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8')
    except:
        return []
    
    events = []
    for line in output.strip().split('\n'):
        if not line: continue
        parts = line.split('\t')
        if len(parts) >= 5:
            # Handle potential NULLs in pc_pid (which might come as 'NULL' string or empty depending on mysql client)
            pid = parts[5] if len(parts) > 5 else '0'
            aid = parts[6] if len(parts) > 6 else '0'
            
            events.append({
                'eid': parts[0],
                'title': parts[1],
                'date': parts[2],
                'start_time': parts[3],
                'duration': parts[4],
                'pid': pid,
                'aid': aid
            })
    return events

events = get_events()
initial_count = $INITIAL_COUNT
current_count = len(events) # This is just the filtered list, not total. 
# Let's get total count separately
try:
    total_cmd = ['docker', 'exec', 'librehealth-db', 'mysql', '-u', 'libreehr', '-ps3cret', 'libreehr', '-N', '-e', 'SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_eventDate = CURDATE()']
    total_count = int(subprocess.check_output(total_cmd).decode('utf-8').strip())
except:
    total_count = 0

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'initial_total_count': initial_count,
    'final_total_count': total_count,
    'events': events,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions for the result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="