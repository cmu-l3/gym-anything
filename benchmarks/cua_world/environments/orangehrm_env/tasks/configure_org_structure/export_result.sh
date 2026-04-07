#!/bin/bash
set -e
echo "=== Exporting configure_org_structure results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_subunit_count.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
echo "Capturing final state..."
take_screenshot /tmp/task_final.png

# 2. Query the Database for the Organization Structure
# We export the entire subunit table to check hierarchy logic in the verifier
# Format: JSON-like list of objects
echo "Querying database for organizational units..."

# Create a temporary SQL script to output JSON
# Note: OrangeHRM DB is MariaDB/MySQL. We'll use CONCAT to build JSON string manually 
# to avoid dependency on modern JSON_OBJECT if the DB version is old, though 5.7+ supports it.
# We'll stick to a safe tab-separated export and convert to JSON in python/bash to be robust.

QUERY="SELECT id, name, unit_id, description, lft, rgt, level FROM ohrm_subunit ORDER BY lft ASC;"
DB_OUTPUT=$(orangehrm_db_query "$QUERY")

# Convert Tab-Separated Values to JSON array using python
# This runs inside the container to generate the result file
python3 -c "
import sys
import json
import csv

data = []
try:
    # input is piped from stdin (the DB_OUTPUT)
    # We need to handle potential empty input
    raw_input = sys.stdin.read().strip()
    if raw_input:
        reader = csv.reader(raw_input.split('\n'), delimiter='\t')
        for row in reader:
            if len(row) >= 7:
                data.append({
                    'id': int(row[0]),
                    'name': row[1],
                    'unit_id': row[2],
                    'description': row[3],
                    'lft': int(row[4]),
                    'rgt': int(row[5]),
                    'level': int(row[6])
                })
except Exception as e:
    sys.stderr.write(f'Error parsing DB output: {e}\n')

print(json.dumps(data))
" <<< "$DB_OUTPUT" > /tmp/org_structure_dump.json

# 3. Create Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_count": $INITIAL_COUNT,
    "final_screenshot_path": "/tmp/task_final.png",
    "db_data": $(cat /tmp/org_structure_dump.json)
}
EOF

# Move to standard location with permissive permissions
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "Found $(grep -c "name" /tmp/org_structure_dump.json) units in database."