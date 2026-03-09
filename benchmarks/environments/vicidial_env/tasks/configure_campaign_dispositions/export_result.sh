#!/bin/bash
set -e

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Capture Final Screenshot
take_screenshot /tmp/task_final.png

# Query Database for Results
# We use a python script inside the container (or passed to it) to get clean JSON
# But simpler is to run python on host (VM) and query via docker exec

echo "Querying Vicidial Database..."

# Create a temporary python script to extract data as JSON
cat > /tmp/extract_statuses.py << 'EOF'
import subprocess
import json
import sys

def run_query(query):
    cmd = [
        "docker", "exec", "vicidial", 
        "mysql", "-ucron", "-p1234", "-D", "asterisk", 
        "-N", "-B", "-e", query
    ]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return result.decode('utf-8')
    except subprocess.CalledProcessError:
        return ""

def main():
    # Get campaign statuses
    # Columns: status, status_name, selectable, human_answered, sale, customer_contact, not_interested, unworkable, scheduled_callback
    cols = "status, status_name, selectable, human_answered, sale, customer_contact, not_interested, unworkable, scheduled_callback"
    query = f"SELECT {cols} FROM vicidial_campaign_statuses WHERE campaign_id='SURVEY01'"
    
    raw_data = run_query(query)
    
    statuses = []
    if raw_data:
        for line in raw_data.strip().split('\n'):
            parts = line.split('\t')
            if len(parts) >= 9:
                statuses.append({
                    "status": parts[0],
                    "status_name": parts[1],
                    "selectable": parts[2],
                    "human_answered": parts[3],
                    "sale": parts[4],
                    "customer_contact": parts[5],
                    "not_interested": parts[6],
                    "unworkable": parts[7],
                    "scheduled_callback": parts[8]
                })

    # Get initial count
    try:
        with open("/tmp/initial_status_count.txt", "r") as f:
            initial_count = int(f.read().strip())
    except:
        initial_count = -1
        
    # Get timestamps
    try:
        with open("/tmp/task_start_time.txt", "r") as f:
            start_time = int(f.read().strip())
    except:
        start_time = 0

    end_time = int(subprocess.check_output(["date", "+%s"]).strip())

    result = {
        "campaign_statuses": statuses,
        "initial_count": initial_count,
        "task_start": start_time,
        "task_end": end_time,
        "screenshot_path": "/tmp/task_final.png"
    }
    
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
EOF

# Run the extraction script
python3 /tmp/extract_statuses.py > /tmp/task_result.json

# Cleanup
rm /tmp/extract_statuses.py

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="