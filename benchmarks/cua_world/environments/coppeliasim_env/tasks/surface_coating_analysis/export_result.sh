#!/bin/bash
echo "=== Exporting surface_coating_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/surface_coating_analysis_start_ts 2>/dev/null || echo "0")
EXPORTS_DIR="/home/ga/Documents/CoppeliaSim/exports"

# Take final screenshot
take_screenshot /tmp/surface_coating_analysis_end_screenshot.png

# Check file timestamps
TRAJ_IS_NEW=false
MAP_IS_NEW=false
REP_IS_NEW=false

if [ -f "$EXPORTS_DIR/trajectory_log.csv" ]; then
    MTIME=$(stat -c %Y "$EXPORTS_DIR/trajectory_log.csv" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && TRAJ_IS_NEW=true
fi

if [ -f "$EXPORTS_DIR/coating_map.csv" ]; then
    MTIME=$(stat -c %Y "$EXPORTS_DIR/coating_map.csv" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && MAP_IS_NEW=true
fi

if [ -f "$EXPORTS_DIR/coating_report.json" ]; then
    MTIME=$(stat -c %Y "$EXPORTS_DIR/coating_report.json" 2>/dev/null || echo "0")
    [ "$MTIME" -gt "$TASK_START" ] && REP_IS_NEW=true
fi

# Run robust Python analysis script to extract CSV and JSON stats
ANALYSIS_JSON=$(python3 << 'PYEOF'
import csv, json, sys, statistics

exports = "/home/ga/Documents/CoppeliaSim/exports"
res = {
    "traj": {"exists": False, "rows": 0, "x_span": 0.0, "y_span": 0.0, "x_std": 0.0, "y_std": 0.0},
    "map": {"exists": False, "rows": 0, "max_th": 0.0, "mean_th": 0.0},
    "rep": {"exists": False, "has_fields": False, "cv": -1.0, "mean": -1.0}
}

# 1. Trajectory Log
try:
    with open(f"{exports}/trajectory_log.csv", "r") as f:
        rows = list(csv.DictReader(f))
    res["traj"]["exists"] = True
    res["traj"]["rows"] = len(rows)
    if rows:
        headers = list(rows[0].keys())
        x_col = next((c for c in headers if 'tcp_x' in c.lower() or c.lower() in ['x', 'actual_x']), None)
        y_col = next((c for c in headers if 'tcp_y' in c.lower() or c.lower() in ['y', 'actual_y']), None)
        if x_col and y_col:
            xs = [float(r[x_col]) for r in rows if r.get(x_col, '').strip()]
            ys = [float(r[y_col]) for r in rows if r.get(y_col, '').strip()]
            if xs and ys:
                res["traj"]["x_span"] = max(xs) - min(xs)
                res["traj"]["y_span"] = max(ys) - min(ys)
                res["traj"]["x_std"] = statistics.stdev(xs) if len(xs) > 1 else 0.0
                res["traj"]["y_std"] = statistics.stdev(ys) if len(ys) > 1 else 0.0
except Exception as e:
    res["traj"]["error"] = str(e)

# 2. Coating Map
try:
    with open(f"{exports}/coating_map.csv", "r") as f:
        rows = list(csv.DictReader(f))
    res["map"]["exists"] = True
    res["map"]["rows"] = len(rows)
    if rows:
        headers = list(rows[0].keys())
        th_col = next((c for c in headers if 'thickness' in c.lower()), None)
        if th_col:
            ths = [float(r[th_col]) for r in rows if r.get(th_col, '').strip()]
            if ths:
                res["map"]["max_th"] = max(ths)
                res["map"]["mean_th"] = sum(ths)/len(ths)
except Exception as e:
    res["map"]["error"] = str(e)

# 3. Coating Report
try:
    with open(f"{exports}/coating_report.json", "r") as f:
        rep = json.load(f)
    res["rep"]["exists"] = True
    req = ['grid_resolution', 'trajectory_duration_s', 'mean_thickness_um', 'min_thickness_um', 'max_thickness_um', 'cv_uniformity']
    res["rep"]["has_fields"] = all(k in rep for k in req)
    res["rep"]["cv"] = float(rep.get('cv_uniformity', -1.0))
    res["rep"]["mean"] = float(rep.get('mean_thickness_um', -1.0))
except Exception as e:
    res["rep"]["error"] = str(e)

print(json.dumps(res))
PYEOF
)

# Combine into final result file
cat > /tmp/surface_coating_result.json << EOF
{
    "task_start": $TASK_START,
    "files_new": {
        "traj": $TRAJ_IS_NEW,
        "map": $MAP_IS_NEW,
        "rep": $REP_IS_NEW
    },
    "analysis": $ANALYSIS_JSON
}
EOF

echo "=== Export Complete ==="