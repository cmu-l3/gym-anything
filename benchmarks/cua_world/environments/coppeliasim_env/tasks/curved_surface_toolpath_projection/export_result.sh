#!/bin/bash
echo "=== Exporting curved_surface_toolpath_projection Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/toolpath.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/toolpath_report.json"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# ---------------------------------------------------------
# 1. API Verification: Query the live scene
# ---------------------------------------------------------
echo "Querying CoppeliaSim scene via API..."
API_RESULT=$(python3 << 'PYEOF'
import sys, json, math
sys.path.insert(0, '/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src')

try:
    from coppeliasim_zmqremoteapi_client import RemoteAPIClient
    client = RemoteAPIClient()
    sim = client.require('sim')

    # Find Sphere
    sphere_found = False
    sphere_center = [0.5, 0.0, 0.1]
    shape_handles = sim.getObjects(sim.scene_type_shape)
    for h in shape_handles:
        try:
            p = sim.getObjectPosition(h, -1)
            dist = math.sqrt((p[0]-0.5)**2 + (p[1]-0.0)**2 + (p[2]-0.1)**2)
            if dist < 0.05:
                sphere_found = True
                break
        except:
            pass

    # Find Dummies
    dummy_handles = sim.getObjects(sim.scene_object_dummy)
    dummy_count = len(dummy_handles)

    correct_standoff_count = 0
    correct_orientation_count = 0

    for h in dummy_handles:
        try:
            p = sim.getObjectPosition(h, -1)
            # matrix is [X.x, Y.x, Z.x, P.x, X.y, Y.y, Z.y, P.y, X.z, Y.z, Z.z, P.z]
            m = sim.getObjectMatrix(h, -1)
            z_axis = [m[2], m[6], m[10]]

            # Distance to center
            dist = math.sqrt((p[0]-0.5)**2 + (p[1]-0.0)**2 + (p[2]-0.1)**2)
            if abs(dist - 0.30) < 0.005: # 0.25 radius + 0.05 standoff, 5mm tol
                correct_standoff_count += 1

            # Vector to center
            v_to_c = [0.5 - p[0], 0.0 - p[1], 0.1 - p[2]]
            v_len = math.sqrt(v_to_c[0]**2 + v_to_c[1]**2 + v_to_c[2]**2)
            if v_len > 0:
                v_to_c = [x/v_len for x in v_to_c]
                dot = sum(a*b for a,b in zip(z_axis, v_to_c))
                if dot > 0.99:
                    correct_orientation_count += 1
        except:
            pass

    print(json.dumps({
        "api_success": True,
        "sphere_found": sphere_found,
        "dummy_count": dummy_count,
        "correct_standoff_count": correct_standoff_count,
        "correct_orientation_count": correct_orientation_count
    }))
except Exception as e:
    print(json.dumps({
        "api_success": False,
        "error": str(e)
    }))
PYEOF
)

# ---------------------------------------------------------
# 2. File Verification: CSV Check
# ---------------------------------------------------------
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        print(len(list(reader)))
except:
    print(0)
" 2>/dev/null || echo "0")
fi

# ---------------------------------------------------------
# 3. File Verification: JSON Check
# ---------------------------------------------------------
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_HAS_FIELDS=false

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_HAS_FIELDS=$(python3 -c "
import json
try:
    with open('$JSON') as f:
        data = json.load(f)
    req = ['total_waypoints','sphere_center_x','sphere_center_y','sphere_center_z','sphere_radius_m','standoff_distance_m']
    print('true' if all(k in data for k in req) else 'false')
except:
    print('false')
" 2>/dev/null || echo "false")
fi

# Write aggregated result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "api_result": ${API_RESULT:-{"api_success": false}},
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_has_fields": $JSON_HAS_FIELDS
}
EOF

echo "Result JSON written."
echo "=== Export Complete ==="