#!/bin/bash
echo "=== Exporting Bulk Update Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task Start: $TASK_START"

# Get Target IDs
TARGET_IDS_JSON=$(cat /tmp/target_req_ids.json 2>/dev/null || echo "[]")
echo "Target IDs: $TARGET_IDS_JSON"

# Create Python script to query DB and verify state
cat > /tmp/verify_db.py << PYEOF
import json
import psycopg2
import os
import sys

# DB Config
DB_NAME = "servicedesk"
DB_USER = "postgres"
DB_PORT = "65432"

try:
    target_ids = $TARGET_IDS_JSON
    if not target_ids:
        print("No target IDs found.")
        sys.exit(0)

    # Convert list to SQL tuple string
    ids_str = ",".join(str(x) for x in target_ids)

    conn = psycopg2.connect(database=DB_NAME, user=DB_USER, host="127.0.0.1", port=DB_PORT)
    cur = conn.cursor()

    # Query details for target requests
    # Tables: workorder (base), workorderstates (assignments)
    # We need: group, category, subcategory names
    query = f"""
    SELECT 
        wo.workorderid,
        qd.queuename as group_name,
        cd.categoryname as category_name,
        scd.name as subcategory_name,
        wos.ap_execution_time as last_updated_ts -- approximations based on available timestamps
    FROM workorder wo
    LEFT JOIN workorderstates wos ON wo.workorderid = wos.workorderid
    LEFT JOIN queuedefinition qd ON wos.queueid = qd.queueid
    LEFT JOIN categorydefinition cd ON wo.categoryid = cd.categoryid
    LEFT JOIN subcategorydefinition scd ON wo.subcategoryid = scd.subcategoryid
    WHERE wo.workorderid IN ({ids_str});
    """
    
    cur.execute(query)
    rows = cur.fetchall()
    
    results = []
    timestamps = []
    
    for row in rows:
        res = {
            "id": row[0],
            "group": row[1],
            "category": row[2],
            "subcategory": row[3],
            "timestamp": row[4]
        }
        results.append(res)
        if row[4]:
            timestamps.append(row[4])

    # Check timestamps for bulk action (spread < 15s)
    bulk_detected = False
    time_spread = 0
    if len(timestamps) > 1:
        time_spread = max(timestamps) - min(timestamps)
        # Note: timestamps in SDP DB are often milliseconds
        if time_spread > 1000000000: # heuristic check if ms or sec
            time_spread = time_spread / 1000
        
        # If spread is small (e.g. < 15 seconds), it's likely a bulk update
        if time_spread < 15: 
            bulk_detected = True

    output = {
        "requests": results,
        "bulk_detected": bulk_detected,
        "time_spread_seconds": time_spread,
        "task_start_ts": $TASK_START
    }

    with open("/tmp/db_verification.json", "w") as f:
        json.dump(output, f, indent=2)

    cur.close()
    conn.close()
    print("Verification data exported.")

except Exception as e:
    print(f"Error verifying DB: {e}")
    # Write empty error result
    with open("/tmp/db_verification.json", "w") as f:
        json.dump({"error": str(e)}, f)

PYEOF

# Execute verification script
python3 /tmp/verify_db.py

# Prepare final JSON for export
# Move to /tmp/task_result.json with permission fixes
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/db_verification.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/db_verification.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Export complete."
cat /tmp/task_result.json