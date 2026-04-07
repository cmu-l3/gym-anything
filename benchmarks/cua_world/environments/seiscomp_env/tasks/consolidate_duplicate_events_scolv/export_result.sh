#!/bin/bash
echo "=== Exporting task results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || import -window root /tmp/task_final.png 2>/dev/null || true

# Extract the state of the events in the database using Python
cat > /tmp/export_db_state.py << 'EOF'
import MySQLdb
import json
import time
import os

result = {
    "events": [],
    "initial_origins": [],
    "error": None
}

try:
    # Read start time
    if os.path.exists("/tmp/task_start_time.txt"):
        with open("/tmp/task_start_time.txt", "r") as f:
            result["task_start_time"] = int(f.read().strip())
    else:
        result["task_start_time"] = 0
        
    result["task_end_time"] = int(time.time())

    # Read initial origins
    if os.path.exists("/tmp/initial_origins.json"):
        with open("/tmp/initial_origins.json", "r") as f:
            result["initial_origins"] = json.load(f)

    # Connect to DB and fetch current state of 2024-01-01 events
    db = MySQLdb.connect(host="localhost", user="sysop", passwd="sysop", db="seiscomp")
    cur = db.cursor()

    cur.execute("""
        SELECT e._oid, e.publicID, e.preferredOriginID
        FROM Event e
        JOIN Origin o ON e.preferredOriginID = o.publicID
        WHERE o.time_value LIKE '2024-01-01%'
    """)
    
    for row in cur.fetchall():
        oid, pubid, pref_orig = row
        # Fetch all origins linked to this event
        cur.execute(f"SELECT originID FROM OriginReference WHERE _parent_oid = {oid}")
        refs = [r[0] for r in cur.fetchall()]
        
        result["events"].append({
            "event_id": pubid,
            "preferred_origin_id": pref_orig,
            "referenced_origins": refs
        })
        
    db.close()

except Exception as e:
    result["error"] = str(e)

# Write to result JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
EOF

python3 /tmp/export_db_state.py

# Ensure permissions are open for the verifier
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="