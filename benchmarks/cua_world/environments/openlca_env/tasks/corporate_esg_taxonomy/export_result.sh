#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Corporate ESG Taxonomy Result ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Check for Report File
REPORT_FILE="/home/ga/LCA_Results/esg_taxonomy_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0) # Encode to avoid JSON issues
fi

# 3. Export Database Tables for Verification
# We need to query TBL_CATEGORIES and TBL_PROCESSES to verify hierarchy
DB_DIR="/home/ga/openLCA-data-1.4/databases"
ACTIVE_DB=""
MAX_SIZE=0

# Find the active database (likely the one modified most recently or largest)
for db_path in "$DB_DIR"/*/; do
    [ -d "$db_path" ] || continue
    DB_SIZE=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
    if [ "${DB_SIZE:-0}" -ge "$MAX_SIZE" ]; then
        MAX_SIZE="${DB_SIZE:-0}"
        ACTIVE_DB="$db_path"
    fi
done

# Need to close OpenLCA to query Derby reliably without locking issues
close_openlca
sleep 3

CATS_JSON="[]"
PROCS_JSON="[]"
DB_FOUND="false"

if [ -n "$ACTIVE_DB" ] && [ -d "$ACTIVE_DB" ]; then
    DB_FOUND="true"
    echo "Querying database: $ACTIVE_DB"

    # Export TBL_CATEGORIES: ID, NAME, F_CATEGORY, MODEL_TYPE
    # We use specific delimiters to parse easily later
    cat_query="SELECT CAST(ID AS CHAR(20)) || '|' || NAME || '|' || COALESCE(CAST(F_CATEGORY AS CHAR(20)), 'NULL') || '|' || MODEL_TYPE FROM TBL_CATEGORIES WHERE MODEL_TYPE = 'PROCESS';"
    CATS_RAW=$(derby_query "$ACTIVE_DB" "$cat_query")
    
    # Export TBL_PROCESSES: ID, NAME, F_CATEGORY
    proc_query="SELECT CAST(ID AS CHAR(20)) || '|' || NAME || '|' || COALESCE(CAST(F_CATEGORY AS CHAR(20)), 'NULL') FROM TBL_PROCESSES;"
    PROCS_RAW=$(derby_query "$ACTIVE_DB" "$proc_query")

    # Save raw outputs to temp files for python parsing
    echo "$CATS_RAW" > /tmp/cats_dump.txt
    echo "$PROCS_RAW" > /tmp/procs_dump.txt
fi

# 4. Construct Result JSON
# We'll let Python handle the heavy parsing of the text dumps, 
# so we just pass file paths or read content if small. 
# Here we'll pass the content of the initial state file too.

INITIAL_STATE_FILE="/tmp/initial_db_state.json"
INITIAL_STATE="{}"
if [ -f "$INITIAL_STATE_FILE" ]; then
    INITIAL_STATE=$(cat "$INITIAL_STATE_FILE")
fi

# Create a python script to parse the derby output into JSON
# This avoids fragile bash string manipulation
python3 -c "
import json
import re

def parse_derby_output(filename, cols):
    data = []
    try:
        with open(filename, 'r') as f:
            lines = f.readlines()
        
        # Derby output usually has headers, dashes, then data, then row count
        # We look for lines containing our delimiter '|'
        for line in lines:
            if '|' in line and not line.startswith('---') and 'SELECT' not in line:
                parts = [p.strip() for p in line.split('|')]
                if len(parts) >= len(cols):
                    row = {}
                    for i, col in enumerate(cols):
                        val = parts[i]
                        if val == 'NULL': val = None
                        row[col] = val
                    data.append(row)
    except Exception as e:
        pass
    return data

cats = parse_derby_output('/tmp/cats_dump.txt', ['ID', 'NAME', 'F_CATEGORY', 'MODEL_TYPE'])
procs = parse_derby_output('/tmp/procs_dump.txt', ['ID', 'NAME', 'F_CATEGORY'])

result = {
    'db_found': '$DB_FOUND' == 'true',
    'active_db_path': '$ACTIVE_DB',
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_content_b64': '$REPORT_CONTENT',
    'initial_state': $INITIAL_STATE,
    'categories': cats,
    'processes': procs,
    'timestamp': $(date +%s)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json | head -c 200
echo "..."