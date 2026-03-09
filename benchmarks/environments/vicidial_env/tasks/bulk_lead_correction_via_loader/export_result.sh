#!/bin/bash
echo "=== Exporting Bulk Lead Correction Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query the database to check the state of the leads
# We need to extract specific fields for the verifier to check:
# 1. phone_number
# 2. city
# 3. entry_date
# 4. lead_id (to check for duplicates)

echo "Querying database..."

# Using python to execute query and format as JSON safely
cat > /tmp/query_leads.py << 'EOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = ["docker", "exec", "vicidial", "mysql", "-ucron", "-p1234", "-D", "asterisk", "-N", "-e", query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.STDOUT).decode('utf-8')
        return result
    except subprocess.CalledProcessError as e:
        print(f"Error running query: {e.output.decode('utf-8')}", file=sys.stderr)
        return ""

# Get leads from list 9999
query = "SELECT phone_number, city, entry_date FROM vicidial_list WHERE list_id='9999' ORDER BY phone_number"
raw_data = run_query(query)

leads = []
for line in raw_data.strip().split('\n'):
    if not line: continue
    parts = line.split('\t')
    if len(parts) >= 3:
        leads.append({
            "phone_number": parts[0].strip(),
            "city": parts[1].strip(),
            "entry_date": parts[2].strip()
        })

# Count total records in list 9999 (to detect duplicates)
count_query = "SELECT COUNT(*) FROM vicidial_list WHERE list_id='9999'"
total_count = run_query(count_query).strip()

result = {
    "leads": leads,
    "total_count": int(total_count) if total_count.isdigit() else 0,
    "screenshot_path": "/tmp/task_final.png"
}

print(json.dumps(result, indent=2))
EOF

# Execute the python script and save result
python3 /tmp/query_leads.py > /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="