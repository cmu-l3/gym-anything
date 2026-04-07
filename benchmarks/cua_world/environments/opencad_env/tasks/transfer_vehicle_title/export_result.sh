#!/bin/bash
echo "=== Exporting transfer_vehicle_title result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve IDs stored during setup
INITIAL_VEH_ID=$(cat /tmp/initial_vehicle_id.txt 2>/dev/null || echo "0")
JOHN_ID=$(cat /tmp/john_id.txt 2>/dev/null || echo "0")
SARAH_ID=$(cat /tmp/sarah_id.txt 2>/dev/null || echo "0")

# Query current state of the vehicle
# We use a small python script to fetch the dictionary cleanly
cat << 'EOF' > /tmp/check_data.py
import pymysql
import json
import sys

def get_connection():
    return pymysql.connect(
        host='127.0.0.1',
        user='opencad',
        password='opencadpass',
        database='opencad',
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )

try:
    conn = get_connection()
    with conn.cursor() as cursor:
        cursor.execute("SELECT id, name_id, plate, color, model FROM ncic_plates WHERE plate = 'XCAV8R'")
        vehicle = cursor.fetchone()
        
    result = {
        "vehicle_found": False,
        "current_vehicle_id": 0,
        "current_owner_id": 0,
        "vehicle_details": {}
    }

    if vehicle:
        result["vehicle_found"] = True
        result["current_vehicle_id"] = vehicle["id"]
        result["current_owner_id"] = vehicle["name_id"]
        result["vehicle_details"] = vehicle

    print(json.dumps(result))

except Exception as e:
    print(json.dumps({"error": str(e)}))
finally:
    try:
        conn.close()
    except:
        pass
EOF

DB_RESULT=$(python3 /tmp/check_data.py)

# Construct final JSON
# We combine the Setup IDs with the DB Result
RESULT_JSON=$(cat << JSON
{
    "initial_vehicle_id": ${INITIAL_VEH_ID},
    "john_id": ${JOHN_ID},
    "sarah_id": ${SARAH_ID},
    "db_state": ${DB_RESULT},
    "timestamp": "$(date -Iseconds)"
}
JSON
)

safe_write_result "$RESULT_JSON" /tmp/transfer_vehicle_title_result.json

echo "Result saved to /tmp/transfer_vehicle_title_result.json"
cat /tmp/transfer_vehicle_title_result.json
echo "=== Export complete ==="