#!/bin/bash
echo "=== Exporting pose_repeatability_study Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/pose_repeatability_study_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/repeatability_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/repeatability_report.json"

# Take final screenshot
take_screenshot /tmp/pose_repeatability_study_end_screenshot.png

# 1. Analyze CSV
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0
CSV_ANALYSIS='{"valid_cols": false, "unique_poses": 0, "min_pose_dist_m": 0.0, "valid_deviations": 0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    CSV_ROW_COUNT=$(python3 -c "
import csv
try:
    with open('$CSV') as f:
        print(len(list(csv.DictReader(f))))
except:
    print(0)
" 2>/dev/null || echo "0")

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, math, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/repeatability_data.csv') as f:
        reader = list(csv.DictReader(f))

    if not reader:
        print(json.dumps({"valid_cols": False, "unique_poses": 0, "min_pose_dist_m": 0.0, "valid_deviations": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in reader[0].keys()]
    pid_col = next((h for h in headers if h in ['pose_id', 'pose']), None)
    mx_col = next((h for h in headers if h in ['measured_x', 'actual_x', 'x']), None)
    my_col = next((h for h in headers if h in ['measured_y', 'actual_y', 'y']), None)
    mz_col = next((h for h in headers if h in ['measured_z', 'actual_z', 'z']), None)
    dev_col = next((h for h in headers if 'deviation' in h or 'error' in h), None)

    valid_cols = all([pid_col, mx_col, my_col, mz_col, dev_col])

    unique_poses = 0
    min_dist = 0.0
    valid_deviations = 0

    if valid_cols:
        poses = {}
        for r in reader:
            # find original case-sensitive column names for extraction
            c_pid = next(k for k in r.keys() if k.strip().lower() == pid_col)
            c_mx = next(k for k in r.keys() if k.strip().lower() == mx_col)
            c_my = next(k for k in r.keys() if k.strip().lower() == my_col)
            c_mz = next(k for k in r.keys() if k.strip().lower() == mz_col)
            c_dev = next(k for k in r.keys() if k.strip().lower() == dev_col)

            pid = str(r[c_pid]).strip()
            try:
                x, y, z = float(r[c_mx]), float(r[c_my]), float(r[c_mz])
                dev = float(r[c_dev])
                if dev >= 0:
                    valid_deviations += 1
                if pid not in poses:
                    poses[pid] = []
                poses[pid].append((x, y, z))
            except Exception:
                pass

        unique_poses = len(poses)
        mean_poses = []
        for pid, pts in poses.items():
            if pts:
                mx = sum(p[0] for p in pts) / len(pts)
                my = sum(p[1] for p in pts) / len(pts)
                mz = sum(p[2] for p in pts) / len(pts)
                mean_poses.append((mx, my, mz))

        dists = []
        for i in range(len(mean_poses)):
            for j in range(i+1, len(mean_poses)):
                p1, p2 = mean_poses[i], mean_poses[j]
                d = math.sqrt((p1[0]-p2[0])**2 + (p1[1]-p2[1])**2 + (p1[2]-p2[2])**2)
                dists.append(d)

        min_dist = min(dists) if dists else 0.0

    print(json.dumps({
        "valid_cols": valid_cols,
        "unique_poses": unique_poses,
        "min_pose_dist_m": min_dist,
        "valid_deviations": valid_deviations
    }))

except Exception as e:
    print(json.dumps({"valid_cols": False, "unique_poses": 0, "min_pose_dist_m": 0.0, "valid_deviations": 0, "error": str(e)}))
PYEOF
    )
fi

# 2. Analyze JSON
JSON_EXISTS=false
JSON_IS_NEW=false
JSON_FIELDS='{"has_fields": false, "total_poses": 0, "trials_per_pose": 0, "iso_compliant": false}'

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_FIELDS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/repeatability_report.json') as f:
        d = json.load(f)
    req = ['total_poses', 'trials_per_pose', 'worst_rp_mm', 'best_rp_mm', 'mean_rp_mm', 'overall_rp_mm', 'iso_compliant']
    has_fields = all(k in d for k in req)
    
    # Handle both string and actual boolean representations
    iso = d.get('iso_compliant', False)
    if isinstance(iso, str):
        iso = iso.lower() == 'true'

    print(json.dumps({
        "has_fields": has_fields,
        "total_poses": int(d.get('total_poses', 0)),
        "trials_per_pose": int(d.get('trials_per_pose', 0)),
        "iso_compliant": bool(iso)
    }))
except Exception as e:
    print(json.dumps({"has_fields": False, "total_poses": 0, "trials_per_pose": 0, "iso_compliant": False, "error": str(e)}))
PYEOF
    )
fi

# 3. Write output
cat > /tmp/pose_repeatability_study_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "=== Export Complete ==="