#!/bin/bash
set -e
echo "=== Setting up materialize_monthly_revenue task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure OrientDB is ready
wait_for_orientdb 120

# Clean state: Drop MonthlyStats if it exists
echo "Cleaning up any previous state..."
orientdb_sql "demodb" "DROP CLASS MonthlyStats UNSAFE" > /dev/null 2>&1 || true

# Generate realistic Orders data using Python
# We generate it dynamically so the agent can't hardcode values
echo "Generating synthetic Orders data..."
cat << 'PY_EOF' > /tmp/generate_data.py
import requests
import json
import random
import datetime
import base64

ORIENT_URL = "http://localhost:2480"
AUTH = ("root", "GymAnything123!")
DB = "demodb"

def sql(cmd):
    try:
        resp = requests.post(
            f"{ORIENT_URL}/command/{DB}/sql",
            auth=AUTH,
            headers={"Content-Type": "application/json"},
            data=json.dumps({"command": cmd}),
            timeout=30
        )
        return resp.json()
    except Exception as e:
        print(f"Error: {e}")
        return {}

# 1. Ensure Orders class exists and is clean
sql("CREATE CLASS Orders IF NOT EXISTS EXTENDS V")
sql("CREATE PROPERTY Orders.Date IF NOT EXISTS DATE")
sql("CREATE PROPERTY Orders.Price IF NOT EXISTS DOUBLE")
sql("CREATE PROPERTY Orders.Status IF NOT EXISTS STRING")
sql("DELETE VERTEX Orders")

# 2. Insert ~150 random records spanning 2 years
statuses = ['paid', 'paid', 'paid', 'pending', 'cancelled', 'refunded']
start_date = datetime.date(2022, 1, 1)

print("Inserting orders...")
batch_cmds = ["begin"]
for _ in range(150):
    day_offset = random.randint(0, 730)
    date_val = (start_date + datetime.timedelta(days=day_offset)).strftime("%Y-%m-%d")
    price = round(random.uniform(20.0, 500.0), 2)
    status = random.choice(statuses)
    
    batch_cmds.append(f"INSERT INTO Orders SET Date='{date_val}', Price={price}, Status='{status}'")

batch_cmds.append("commit")

# Execute as a batch script to be faster
script_body = ";\n".join(batch_cmds)
resp = requests.post(
    f"{ORIENT_URL}/batch/{DB}",
    auth=AUTH,
    headers={"Content-Type": "application/json"},
    data=json.dumps({"operations": [{"type": "script", "language": "sql", "script": script_body}]})
)
print(f"Data generation status: {resp.status_code}")
PY_EOF

# Run the generator
python3 /tmp/generate_data.py

# Verify data was inserted
ORDER_COUNT=$(orientdb_sql "demodb" "SELECT count(*) as cnt FROM Orders" | jq -r '.result[0].cnt')
echo "Orders populated: $ORDER_COUNT records"

# Launch Firefox to OrientDB Studio
echo "Launching OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="