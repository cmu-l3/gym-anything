#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Results ==="

# 1. Capture final state screenshot
take_screenshot "/tmp/task_final.png"

# 2. Get Task Start Time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Get Mailbox IDs
SALES_MB_ID=$(find_mailbox_by_name "Sales" | awk '{print $1}')
SUPPORT_MB_ID=$(find_mailbox_by_name "Support" | awk '{print $1}')

# 4. Gather data on Targets
# We use JSON structure building via python to be robust
cat > /tmp/collect_data.py << EOF
import json
import subprocess
import sys

def run_query(query):
    cmd = ["docker", "exec", "freescout-db", "mysql", "-u", "freescout", "-pfreescout123", "freescout", "-N", "-e", query]
    try:
        result = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8').strip()
        return result
    except:
        return ""

def get_conv_data(keyword):
    # Get id, subject, mailbox_id, updated_at
    query = f"SELECT id, subject, mailbox_id, updated_at FROM conversations WHERE subject LIKE '%{keyword}%'"
    raw = run_query(query)
    results = []
    if raw:
        for line in raw.split('\n'):
            parts = line.split('\t')
            if len(parts) >= 4:
                results.append({
                    "id": parts[0],
                    "subject": parts[1],
                    "mailbox_id": parts[2],
                    "updated_at": parts[3]
                })
    return results

data = {
    "start_time": $START_TIME,
    "sales_mailbox_id": "$SALES_MB_ID",
    "support_mailbox_id": "$SUPPORT_MB_ID",
    "targets": [],
    "distractors": []
}

# Collect Targets
target_keywords = ["Purchase Order #3021", "Purchase Order #3022", "Purchase Order #3023", "Purchase Order #3024", "Purchase Order #3025"]
for kw in target_keywords:
    res = get_conv_data(kw)
    if res:
        data["targets"].extend(res)

# Collect Distractors
distractor_keywords = ["Printer Jam", "Login failed", "coffee machine"]
for kw in distractor_keywords:
    res = get_conv_data(kw)
    if res:
        data["distractors"].extend(res)

print(json.dumps(data, indent=2))
EOF

python3 /tmp/collect_data.py > /tmp/task_result.json 2>/dev/null

# Safe copy to output location
safe_write_result "/tmp/task_result.json" "/tmp/task_result.json"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json