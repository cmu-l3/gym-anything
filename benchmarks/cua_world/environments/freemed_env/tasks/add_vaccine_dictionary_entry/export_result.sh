#!/bin/bash
# Export script for add_vaccine_dictionary_entry task

echo "=== Exporting Task Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create final database dump
echo "Creating final database dump..."
mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null > /tmp/freemed_final.sql

# Extract newly inserted rows by diffing the initial and final SQL dumps
echo "Extracting database insertions..."
comm -13 <(sort /tmp/freemed_initial.sql) <(sort /tmp/freemed_final.sql) > /tmp/new_inserts.txt

# Use Python to safely package the exported data into JSON
python3 << 'PYEOF'
import json
import os

new_inserts = ""
if os.path.exists('/tmp/new_inserts.txt'):
    with open('/tmp/new_inserts.txt', 'r', encoding='utf-8', errors='ignore') as f:
        new_inserts = f.read()

bash_history = ""
if os.path.exists('/home/ga/.bash_history'):
    with open('/home/ga/.bash_history', 'r', encoding='utf-8', errors='ignore') as f:
        bash_history = f.read()

mysql_history_exists = os.path.exists('/home/ga/.mysql_history')
screenshot_exists = os.path.exists('/tmp/task_final.png')

result = {
    "new_inserts": new_inserts,
    "bash_history": bash_history,
    "mysql_history_exists": mysql_history_exists,
    "screenshot_exists": screenshot_exists,
    "export_timestamp": os.popen('date -Iseconds').read().strip()
}

temp_json = '/tmp/vaccine_result.tmp.json'
final_json = '/tmp/task_result.json'

with open(temp_json, 'w') as f:
    json.dump(result, f)

os.system(f'mv {temp_json} {final_json}')
os.system(f'chmod 666 {final_json}')
PYEOF

echo "Result JSON saved to /tmp/task_result.json"
echo "=== Export Complete ==="