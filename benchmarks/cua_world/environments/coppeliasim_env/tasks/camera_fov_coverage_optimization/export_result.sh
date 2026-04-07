#!/bin/bash
echo "=== Exporting camera_fov_coverage_optimization Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/camera_fov_coverage_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/camera_coverage_sweep.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/optimal_camera_placement.json"
PY="/home/ga/Documents/CoppeliaSim/exports/coverage_script.py"
TTT="/home/ga/Documents/CoppeliaSim/exports/optimized_scene.ttt"

# Take final evidence screenshot
take_screenshot /tmp/camera_fov_coverage_end_screenshot.png

# Check file existence and modification timestamps
CSV_EXISTS=false; CSV_IS_NEW=false
JSON_EXISTS=false; JSON_IS_NEW=false
PY_EXISTS=false; PY_IS_NEW=false
TTT_EXISTS=false; TTT_IS_NEW=false

if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    [ "$(stat -c %Y "$CSV" 2>/dev/null || echo 0)" -gt "$TASK_START" ] && CSV_IS_NEW=true
fi
if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    [ "$(stat -c %Y "$JSON" 2>/dev/null || echo 0)" -gt "$TASK_START" ] && JSON_IS_NEW=true
fi
if [ -f "$PY" ]; then
    PY_EXISTS=true
    [ "$(stat -c %Y "$PY" 2>/dev/null || echo 0)" -gt "$TASK_START" ] && PY_IS_NEW=true
fi
if [ -f "$TTT" ]; then
    TTT_EXISTS=true
    [ "$(stat -c %Y "$TTT" 2>/dev/null || echo 0)" -gt "$TASK_START" ] && TTT_IS_NEW=true
fi

# Parse the CSV using Python to ensure dimensions and data logic are valid
CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/camera_coverage_sweep.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    if not rows:
        print(json.dumps({"has_cols": False, "row_count": 0}))
        sys.exit(0)
    
    headers = list(rows[0].keys())
    def find_col(candidates):
        hl = [h.strip().lower() for h in headers]
        for c in candidates:
            if c in hl: return headers[hl.index(c)]
        return None
        
    z_col = find_col(['z_m', 'z', 'height', 'height_m'])
    p_col = find_col(['pitch_deg', 'pitch', 'angle_deg', 'angle'])
    v_col = find_col(['visible_count', 'visible', 'count'])
    
    if z_col and p_col and v_col:
        zs = [float(r[z_col]) for r in rows if r.get(z_col, '').strip()]
        ps = [float(r[p_col]) for r in rows if r.get(p_col, '').strip()]
        vs = [int(float(r[v_col])) for r in rows if r.get(v_col, '').strip()]
        
        print(json.dumps({
            "has_cols": True,
            "row_count": len(rows),
            "unique_z": len(set(zs)),
            "unique_p": len(set(ps)),
            "unique_v": len(set(vs)),
            "max_v": max(vs) if vs else 0,
            "valid_v": all(0 <= v <= 9 for v in vs) if vs else False
        }))
    else:
        print(json.dumps({"has_cols": False, "row_count": len(rows)}))
except Exception as e:
    print(json.dumps({"has_cols": False, "row_count": 0, "error": str(e)}))
PYEOF
)

# Parse the JSON report
JSON_ANALYSIS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/optimal_camera_placement.json') as f:
        d = json.load(f)
    req = ['total_poses_tested', 'max_visible_count', 'optimal_z_m', 'optimal_pitch_deg']
    print(json.dumps({
        "has_fields": all(k in d for k in req),
        "total": int(d.get('total_poses_tested', 0)),
        "max_v": int(d.get('max_visible_count', 0))
    }))
except Exception as e:
    print(json.dumps({"has_fields": False, "error": str(e)}))
PYEOF
)

# Explicit Anti-Gaming Check: Ensure the Python script actually interacts with CoppeliaSim API
SCRIPT_HAS_API=false
if [ "$PY_EXISTS" = true ]; then
    if grep -q "sim\." "$PY"; then
        SCRIPT_HAS_API=true
    fi
fi

# Write summary JSON for verifier.py
cat > /tmp/camera_fov_coverage_result.json << EOF
{
    "task_start": $TASK_START,
    "files": {
        "csv": {"exists": $CSV_EXISTS, "new": $CSV_IS_NEW},
        "json": {"exists": $JSON_EXISTS, "new": $JSON_IS_NEW},
        "py": {"exists": $PY_EXISTS, "new": $PY_IS_NEW, "has_api": $SCRIPT_HAS_API},
        "ttt": {"exists": $TTT_EXISTS, "new": $TTT_IS_NEW}
    },
    "csv_analysis": $CSV_ANALYSIS,
    "json_analysis": $JSON_ANALYSIS
}
EOF

echo "=== Export Complete ==="