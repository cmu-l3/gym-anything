#!/bin/bash
echo "=== Exporting shortest_path_social_network results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULT_FILE="/home/ga/shortest_path_results.json"

# Check file status
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE="0"

if [ -f "$RESULT_FILE" ]; then
    OUTPUT_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$RESULT_FILE")
    FILE_MTIME=$(stat -c %Y "$RESULT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Generate Ground Truth and Compare inside the container
# We use a Python script to query the DB for the ACTUAL current state
# and package everything into the result JSON
python3 << 'PYEOF' > /tmp/task_result.json
import json
import os
import urllib.request
import base64
import time

# --- Configuration ---
RESULT_FILE = "/home/ga/shortest_path_results.json"
DB_URL = "http://localhost:2480"
AUTH = base64.b64encode(b"root:GymAnything123!").decode()
HEADERS = {"Authorization": f"Basic {AUTH}", "Content-Type": "application/json"}

def sql_query(command):
    try:
        req = urllib.request.Request(
            f"{DB_URL}/command/demodb/sql",
            data=json.dumps({"command": command}).encode(),
            headers=HEADERS,
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()).get("result", [])
    except Exception as e:
        return []

def get_shortest_path(email_from, email_to):
    # OrientDB shortestPath function
    # Note: Using BOTH for bidirectional traversal on HasFriend edge
    query = f"SELECT shortestPath((SELECT FROM Profiles WHERE Email='{email_from}'), (SELECT FROM Profiles WHERE Email='{email_to}'), 'BOTH', 'HasFriend') as path"
    res = sql_query(query)
    if not res or not res[0].get("path"):
        return {"hops": 0, "path_emails": []}
    
    rids = res[0]["path"] # List of RIDs
    if not rids:
        return {"hops": 0, "path_emails": []}
        
    # Fetch emails for these RIDs to normalize
    # Create a query to fetch all emails for the RIDs in the path
    rid_str = ", ".join([f"{rid}" for rid in rids])
    profile_res = sql_query(f"SELECT @rid, Email FROM Profiles WHERE @rid IN [{rid_str}]")
    
    # Map RID to Email
    rid_map = {p["@rid"]: p["Email"] for p in profile_res}
    
    # Reconstruct path in order
    path_emails = [rid_map.get(rid, "UNKNOWN") for rid in rids]
    
    return {
        "hops": len(rids) - 1,
        "path_emails": path_emails
    }

def get_fof(email_center):
    # Friends of Friends: 2 hops away, excluding center and direct friends
    # Traverse: Profile -> HasFriend -> Profile -> HasFriend -> Profile
    # Since edges are directed but we treat as bidirectional for friendship, logic is complex in SQL.
    # Simpler: Use TRAVERSE or nested SELECTs assuming bidirectional traversal
    
    # Using shortestPath checks for depth 2 is safer but slow for all nodes.
    # Let's use OrientDB's TRAVERSE or pattern match.
    # "SELECT expand(both('HasFriend').both('HasFriend')) FROM Profiles WHERE Email='...'" includes center and depth 1.
    
    query = f"SELECT Email FROM (SELECT expand(both('HasFriend').both('HasFriend')) FROM Profiles WHERE Email='{email_center}') WHERE Email <> '{email_center}' AND Email NOT IN (SELECT Email FROM (SELECT expand(both('HasFriend')) FROM Profiles WHERE Email='{email_center}'))"
    
    res = sql_query(query)
    fof_emails = list(set([r["Email"] for r in res])) # Deduplicate
    return fof_emails

# --- 1. Load Agent Output ---
agent_data = {}
try:
    if os.path.exists(RESULT_FILE):
        with open(RESULT_FILE, 'r') as f:
            agent_data = json.load(f)
except Exception:
    pass

# --- 2. Calculate Ground Truth ---
gt_schafer = get_shortest_path("john.smith@example.com", "thomas.schafer@example.com")
gt_petrakis = get_shortest_path("john.smith@example.com", "elena.petrakis@example.com")
gt_tanaka_path = get_shortest_path("john.smith@example.com", "yuki.tanaka@example.com")
gt_tanaka_exists = len(gt_tanaka_path["path_emails"]) > 0
gt_fof = get_fof("john.smith@example.com")

ground_truth = {
    "path_to_schafer": gt_schafer,
    "path_to_petrakis": gt_petrakis,
    "path_to_tanaka_exists": gt_tanaka_exists,
    "friends_of_friends": sorted(gt_fof)
}

# --- 3. Construct Final Result ---
final_result = {
    "task_info": {
        "start": int(os.environ.get("TASK_START", 0)),
        "end": int(time.time()),
        "output_exists": os.environ.get("OUTPUT_EXISTS") == "true",
        "file_created_during_task": os.environ.get("FILE_CREATED_DURING_TASK") == "true",
        "screenshot_path": "/tmp/task_final.png"
    },
    "agent_output": agent_data,
    "ground_truth": ground_truth
}

print(json.dumps(final_result))
PYEOF

# Fix permissions
cp /tmp/task_result.json /tmp/task_result_final.json
chmod 666 /tmp/task_result_final.json

echo "Export complete."
cat /tmp/task_result_final.json