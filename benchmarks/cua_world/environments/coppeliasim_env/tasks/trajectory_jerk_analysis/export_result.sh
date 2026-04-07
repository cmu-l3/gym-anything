#!/bin/bash
echo "=== Exporting trajectory_jerk_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/trajectory_jerk_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/trajectory_samples.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/smoothness_report.json"

# Take final screenshot
take_screenshot /tmp/trajectory_jerk_analysis_end_screenshot.png

# Check CSV file
CSV_EXISTS=false
CSV_IS_NEW=false
CSV_ROW_COUNT=0

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true

    # Count data rows (exclude header)
    CSV_ROW_COUNT=$(python3 -c "
import csv, sys
try:
    with open('$CSV') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    print(len(rows))
except:
    print(0)
" 2>/dev/null || echo "0")

    # Analyze trajectory data (path length, derivatives validity, monotonicity)
    CSV_STATS=$(python3 << 'PYEOF'
import csv, sys, json, math
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/trajectory_samples.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"error": "empty csv"}))
        sys.exit(0)

    def find_col(headers, candidates):
        hl = [h.strip().lower() for h in headers]
        for c in candidates:
            if c in hl: return headers[hl.index(c)]
        return None

    headers = list(rows[0].keys())
    t_col = find_col(headers, ['timestamp_s','time_s','time','timestamp','t'])
    x_col = find_col(headers, ['x_m','x','px','pos_x'])
    y_col = find_col(headers, ['y_m','y','py','pos_y'])
    z_col = find_col(headers, ['z_m','z','pz','pos_z'])
    v_col = find_col(headers, ['velocity_m_s','velocity','v','vel'])
    a_col = find_col(headers, ['acceleration_m_s2','acceleration','accel','a'])
    j_col = find_col(headers, ['jerk_m_s3','jerk','j'])

    has_coords = bool(x_col and y_col and z_col and t_col)
    has_derivs = bool(v_col and a_col and j_col)

    path_len = 0.0
    monotonic = True
    finite_jerk_count = 0
    max_jerk = 0.0

    if has_coords:
        prev_t, prev_x, prev_y, prev_z = None, None, None, None
        for r in rows:
            try:
                t = float(r[t_col])
                x = float(r[x_col])
                y = float(r[y_col])
                z = float(r[z_col])
                if prev_t is not None:
                    if t < prev_t: monotonic = False
                    dist = math.sqrt((x-prev_x)**2 + (y-prev_y)**2 + (z-prev_z)**2)
                    path_len += dist
                prev_t, prev_x, prev_y, prev_z = t, x, y, z
            except: pass

    if has_derivs:
        for r in rows:
            try:
                j_val = float(r[j_col])
                if not math.isnan(j_val) and not math.isinf(j_val):
                    finite_jerk_count += 1
                    max_jerk = max(max_jerk, abs(j_val))
            except: pass

    print(json.dumps({
        "has_coords": has_coords,
        "has_derivs": has_derivs,
        "path_len": path_len,
        "monotonic": monotonic,
        "finite_jerk_ratio": finite_jerk_count / len(rows) if rows else 0,
        "max_jerk": max_jerk
    }))
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF
    )
else:
    CSV_STATS="{}"
fi

# Check JSON report file
JSON_EXISTS=false
JSON_IS_NEW=false

if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true

    JSON_INFO=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        data = json.load(f)
    required = ['total_samples', 'total_waypoints', 'duration_s', 'avg_velocity_m_s', 'max_acceleration_m_s2', 'max_jerk_m_s3', 'rms_jerk_m_s3', 'smooth_segment_pct']
    has_fields = all(k in data for k in required)
    print(json.dumps({
        'has_fields': has_fields,
        'total_samples': int(data.get('total_samples', 0)),
        'total_waypoints': int(data.get('total_waypoints', 0)),
        'rms_jerk_m_s3': float(data.get('rms_jerk_m_s3', 0))
    }))
except Exception as e:
    print(json.dumps({'error': str(e), 'has_fields': False}))
" 2>/dev/null || echo '{"has_fields": false}')
else:
    JSON_INFO="{}"
fi

# Write result JSON for verifier
cat > /tmp/trajectory_jerk_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "csv_stats": $CSV_STATS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_info": $JSON_INFO
}
EOF

echo "=== Export Complete ==="