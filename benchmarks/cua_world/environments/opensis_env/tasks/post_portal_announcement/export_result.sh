#!/bin/bash
echo "=== Exporting post_portal_announcement results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_notes_count.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Query the database for the created note
# We search for the specific title created in the task
# Note: Column names for audience permissions in OpenSIS portal_notes table typically:
# published_profiles (serialized) OR individual columns like student, parent, etc.
# We will select * and parse in python to be safe against schema variations,
# or select specific likely columns if we are sure.
# Based on OpenSIS schema, it often uses 'published_profiles' or specific columns. 
# We'll dump the relevant row to JSON-like structure.

echo "Querying database..."
NOTE_DATA=$(mysql -u opensis_user -p'opensis_password_123' opensis -B -e "SELECT * FROM portal_notes WHERE title='Spring Science Fair' ORDER BY id DESC LIMIT 1" 2>/dev/null)

# Check if a note was found
NOTE_FOUND="false"
if [ -n "$NOTE_DATA" ]; then
    NOTE_FOUND="true"
fi

# Get current total count
CURRENT_COUNT=$(mysql -u opensis_user -p'opensis_password_123' opensis -N -e "SELECT COUNT(*) FROM portal_notes" 2>/dev/null || echo "0")

# 3. Create JSON Result
# We use python to safely format the MySQL output to JSON
python3 -c "
import sys
import json
import csv
import io

try:
    task_start = $TASK_START
    initial_count = int('$INITIAL_COUNT')
    current_count = int('$CURRENT_COUNT')
    note_found = '$NOTE_FOUND' == 'true'
    
    # Raw MySQL output (Tab Separated)
    raw_data = sys.stdin.read()
    
    note_record = {}
    if note_found and raw_data.strip():
        # Parse TSV
        reader = csv.DictReader(io.StringIO(raw_data), delimiter='\t')
        for row in reader:
            note_record = row
            break # Only need the first (latest) one

    result = {
        'task_start': task_start,
        'initial_count': initial_count,
        'current_count': current_count,
        'note_found': note_found,
        'note_record': note_record,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=2)
        
except Exception as e:
    # Fallback in case of error
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'note_found': False}, f)

" <<< "$NOTE_DATA"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="