#!/bin/bash
echo "=== Exporting Deduplication Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check report file
REPORT_PATH="/home/ga/dedup_report.txt"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_VALID_TIME="true"
    else
        REPORT_VALID_TIME="false"
    fi
else
    REPORT_EXISTS="false"
    REPORT_CONTENT=""
    REPORT_VALID_TIME="false"
fi

# Create Python verification script to check DB state
cat > /tmp/verify_db.py << 'PYEOF'
import urllib.request
import json
import base64
import sys

# Configuration
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"admin:admin").decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}

def sql(command):
    data = json.dumps({"command": command}).encode()
    req = urllib.request.Request(
        f"{BASE_URL}/command/demodb/sql",
        data=data, headers=HEADERS, method="POST"
    )
    try:
        with urllib.request.urlopen(req) as resp:
            return json.loads(resp.read())
    except Exception as e:
        return {"error": str(e)}

def check_edge(from_email, to_hotel_name, edge_class="HasStayed"):
    # Check if edge exists from Profile(email) to Hotel(name)
    query = (
        f"SELECT count(*) as cnt FROM {edge_class} "
        f"WHERE out.Email = '{from_email}' AND in.Name = '{to_hotel_name}'"
    )
    res = sql(query)
    return res.get('result', [{}])[0].get('cnt', 0) > 0

def check_friend_edge(from_email, to_email):
    query = (
        f"SELECT count(*) as cnt FROM HasFriend "
        f"WHERE out.Email = '{from_email}' AND in.Email = '{to_email}'"
    )
    res = sql(query)
    return res.get('result', [{}])[0].get('cnt', 0) > 0

results = {}

# 1. Check for duplicates (Goal: 0)
h_dups = sql("SELECT count(*) as cnt FROM (SELECT Name, City, count(*) as c FROM Hotels GROUP BY Name, City) WHERE c > 1")
p_dups = sql("SELECT count(*) as cnt FROM (SELECT Email, count(*) as c FROM Profiles GROUP BY Email) WHERE c > 1")

results['hotel_dup_groups'] = h_dups.get('result', [{}])[0].get('cnt', -1)
results['profile_dup_groups'] = p_dups.get('result', [{}])[0].get('cnt', -1)

# 2. Check Edge Preservation (Critical: Edges must exist on originals now)
# We know the originals based on unique Name/City or Email
# Luca -> Hotel Artemide
results['edge_luca_artemide'] = check_edge('luca.rossi@example.com', 'Hotel Artemide')
# Anna -> Hotel Artemide
results['edge_anna_artemide'] = check_edge('anna.mueller@example.com', 'Hotel Artemide')
# James -> The Savoy
results['edge_james_savoy'] = check_edge('james.brown@example.com', 'The Savoy')
# Emma -> Copacabana Palace
results['edge_emma_copacabana'] = check_edge('emma.white@example.com', 'Copacabana Palace')

# Carlos -> John Smith
results['edge_carlos_john'] = check_friend_edge('carlos.lopez@example.com', 'john.smith@example.com')
# Emma -> Yuki Tanaka
results['edge_emma_yuki'] = check_friend_edge('emma.white@example.com', 'yuki.tanaka@example.com')
# Yuki Tanaka -> James Brown
results['edge_yuki_james'] = check_friend_edge('yuki.tanaka@example.com', 'james.brown@example.com')

# 3. Check Index Restoration
idx_res = sql("SELECT FROM metadata:indexmanager")
indexes = []
if 'result' in idx_res:
    for r in idx_res['result']:
        if 'indexes' in r:
            for i in r['indexes']:
                 indexes.append(i)

# Find Profiles.Email unique index
index_found = False
for idx in indexes:
    if idx.get('name') == 'Profiles.Email' and idx.get('type') == 'UNIQUE':
        index_found = True
        break
results['index_restored'] = index_found

print(json.dumps(results))
PYEOF

# Run verification script
DB_RESULTS=$(python3 /tmp/verify_db.py)

# Generate JSON result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_VALID_TIME,
    "report_content_b64": "$REPORT_CONTENT",
    "db_state": $DB_RESULTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"