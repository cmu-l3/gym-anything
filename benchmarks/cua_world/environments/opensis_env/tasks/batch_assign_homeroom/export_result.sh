#!/bin/bash
echo "=== Exporting batch_assign_homeroom result ==="

DB_USER="opensis_user"
DB_PASS="opensis_password_123"
DB_NAME="opensis"

# 1. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Read Target IDs
# Format of /tmp/target_students.txt is: ID \t First \t Last
if [ ! -f /tmp/target_students.txt ]; then
    echo "Error: Target student list not found."
    exit 1
fi

# Build ID list for query
IDS=$(awk '{print $1}' /tmp/target_students.txt | paste -sd, -)
echo "Checking students with IDs: $IDS"

# 3. Query Database for Final State
# We select ID, First, Last, and Homeroom for the specific students created in setup
QUERY="SELECT student_id, first_name, last_name, homeroom FROM students WHERE student_id IN ($IDS);"

# Execute query and format as JSON
# Using python for robust JSON generation from TSV output
mysql -u $DB_USER -p$DB_PASS $DB_NAME -N -B -e "$QUERY" > /tmp/query_result.tsv

# Generate JSON
python3 -c "
import json
import csv
import sys
import time

results = []
try:
    with open('/tmp/query_result.tsv', 'r') as f:
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 4:
                results.append({
                    'student_id': row[0],
                    'first_name': row[1],
                    'last_name': row[2],
                    'homeroom': row[3] if row[3] != 'NULL' else None
                })
except Exception as e:
    print(f'Error parsing DB results: {e}', file=sys.stderr)

output = {
    'task_timestamp': time.time(),
    'students': results,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json