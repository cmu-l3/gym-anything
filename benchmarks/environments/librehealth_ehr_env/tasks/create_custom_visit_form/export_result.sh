#!/bin/bash
echo "=== Exporting Create Custom Visit Form Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the layout_options table to see if the form was created
# We export the results to a JSON file for the Python verifier to parse
# We check for rows related to 'LBF_Neuro'
echo "Querying layout_options table..."

# Create a temporary SQL dump file
SQL_RESULT_FILE="/tmp/layout_dump.txt"

# Select key columns: form_id, field_id, group_id, title, data_type
# data_type: 0 usually implies structural, 1=text, etc.
librehealth_query "SELECT form_id, field_id, group_id, title, data_type, uor FROM layout_options WHERE form_id = 'LBF_Neuro' OR title LIKE '%Neurology%' OR title LIKE '%Reflex%' ORDER BY seq" > "$SQL_RESULT_FILE" 2>/dev/null || true

# Convert the SQL text dump to a simple JSON structure using python
# This is safer than trying to format JSON directly in SQL
python3 -c "
import json
import csv
import sys

rows = []
try:
    with open('$SQL_RESULT_FILE', 'r') as f:
        # Assuming tab-separated output from mysql -N
        reader = csv.reader(f, delimiter='\t')
        for row in reader:
            if len(row) >= 4:
                record = {
                    'form_id': row[0],
                    'field_id': row[1],
                    'group_id': row[2],
                    'title': row[3],
                    'data_type': row[4] if len(row) > 4 else '',
                    'uor': row[5] if len(row) > 5 else ''
                }
                rows.append(record)
except Exception as e:
    sys.stderr.write(str(e))

output = {
    'layout_rows': rows,
    'timestamp': '$(date +%s)',
    'screenshot_exists': True
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(output, f, indent=2)
"

# Set permissions so the host can copy it
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json