#!/bin/bash
echo "=== Exporting Create Technician Group Results ==="

source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Task Timings
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_GROUP_COUNT=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# 3. Query Database for Results
# We use a Python script to extract structured data about the group and its members
cat > /tmp/check_group.py << 'PYEOF'
import psycopg2
import json
import sys

def get_db_connection():
    try:
        return psycopg2.connect(host="127.0.0.1", port="65432", database="servicedesk", user="postgres")
    except:
        return psycopg2.connect(host="127.0.0.1", port="65432", database="servicedesk", user="sdpadmin")

def get_group_info(group_name):
    conn = get_db_connection()
    cur = conn.cursor()
    
    result = {
        "found": False,
        "id": None,
        "name": None,
        "description": None,
        "creation_time": 0,
        "members": []
    }
    
    try:
        # Find group by name (case-insensitive)
        # Note: Table names in SDP might vary by version, but TechnicianGroup is standard
        # Fallback tables: SDTechGroup, ResourceGroup if TechnicianGroup fails (but usually it's TechnicianGroup or similar)
        
        # Checking TechnicianGroup / SDTechGroup
        # Columns usually: GROUPID, NAME, DESCRIPTION, CREATEDTIME
        query = "SELECT GROUPID, NAME, DESCRIPTION, CREATEDTIME FROM TechnicianGroup WHERE LOWER(NAME) = LOWER(%s)"
        cur.execute(query, (group_name,))
        row = cur.fetchone()
        
        if row:
            result["found"] = True
            result["id"] = row[0]
            result["name"] = row[1]
            result["description"] = row[2]
            result["creation_time"] = row[3] if row[3] else 0
            
            # Get Members
            # Membership table is usually ResourceToGroup (GROUPID, RESOURCEID) or TechGroupMembers
            # And we need to join with AaaUser/AaaLogin to get names
            
            mem_query = """
                SELECT al.NAME 
                FROM ResourceToGroup rtg
                JOIN AaaUser au ON rtg.RESOURCEID = au.USER_ID
                JOIN AaaLogin al ON au.USER_ID = al.USER_ID
                WHERE rtg.GROUPID = %s
            """
            cur.execute(mem_query, (row[0],))
            members = cur.fetchall()
            result["members"] = [m[0] for m in members]
            
    except Exception as e:
        result["error"] = str(e)
    finally:
        conn.close()
        
    return result

# Target group name
group_data = get_group_info("Network Operations Center")

# Dump to JSON
print(json.dumps(group_data))
PYEOF

GROUP_JSON=$(python3 /tmp/check_group.py 2>/dev/null || echo '{"found": false, "error": "Script failed"}')
CURRENT_GROUP_COUNT=$(sdp_db_exec "SELECT COUNT(*) FROM techniciangroup;" 2>/dev/null || echo "0")

# 4. Construct Final Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_group_count": $INITIAL_GROUP_COUNT,
    "current_group_count": $CURRENT_GROUP_COUNT,
    "group_data": $GROUP_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# 5. Save to protected location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="