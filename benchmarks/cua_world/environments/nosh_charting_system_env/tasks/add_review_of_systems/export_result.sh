#!/bin/bash
echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# ============================================================
# Query NOSH Database for Result
# ============================================================

# We look for the ROS entry associated with eid=999
# We select all relevant columns
QUERY="SELECT 
    ros_id, eid, pid, date, 
    ros_gen, ros_eye, ros_ent, ros_resp, ros_cv, ros_gi, ros_gu, 
    ros_mus, ros_neuro, ros_psych, ros_hemi, ros_skin, ros_endocrine 
    FROM ros WHERE eid=999 ORDER BY ros_id DESC LIMIT 1"

# Execute query inside container and output JSON-like structure
# We use python inside the container or on host to format sql output to json if possible, 
# but simple mysql query with tab separation is easier to parse in verifier.py
echo "Querying database..."
ROS_DATA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "$QUERY" 2>/dev/null || echo "")

# Check if data was found
ROS_FOUND="false"
if [ -n "$ROS_DATA" ]; then
    ROS_FOUND="true"
fi

# ============================================================
# Count total ROS records (to detect creation)
# ============================================================
FINAL_ROS_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM ros WHERE eid=999" 2>/dev/null || echo "0")
INITIAL_ROS_COUNT=$(cat /tmp/initial_ros_count.txt 2>/dev/null || echo "0")

# ============================================================
# Check Application State
# ============================================================
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# ============================================================
# Capture Final Screenshot
# ============================================================
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ============================================================
# Create JSON Result
# ============================================================
# We use python to safely construct JSON from the raw text data to handle special chars/newlines
python3 -c "
import json
import sys
import time

try:
    ros_found = '$ROS_FOUND' == 'true'
    ros_data_raw = '''$ROS_DATA'''
    
    ros_record = {}
    if ros_found and ros_data_raw.strip():
        # Columns in order of query: 
        # ros_id, eid, pid, date, ros_gen, ros_eye, ros_ent, ros_resp, ros_cv, ros_gi, ros_gu, ros_mus, ros_neuro, ros_psych, ros_hemi, ros_skin, ros_endocrine
        keys = ['ros_id', 'eid', 'pid', 'date', 'ros_gen', 'ros_eye', 'ros_ent', 'ros_resp', 'ros_cv', 'ros_gi', 'ros_gu', 'ros_mus', 'ros_neuro', 'ros_psych', 'ros_hemi', 'ros_skin', 'ros_endocrine']
        values = ros_data_raw.strip().split('\t')
        
        # Safe zip
        for i, key in enumerate(keys):
            if i < len(values):
                ros_record[key] = values[i]
            else:
                ros_record[key] = ''

    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'ros_found': ros_found,
        'ros_record': ros_record,
        'initial_count': int('$INITIAL_ROS_COUNT'),
        'final_count': int('$FINAL_ROS_COUNT'),
        'app_was_running': '$APP_RUNNING' == 'true',
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f, indent=4)
        
except Exception as e:
    print(f'Error creating JSON: {e}', file=sys.stderr)
    # Fallback minimal JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'ros_found': False}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="