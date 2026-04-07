#!/bin/bash
echo "=== Exporting dual_robot_welding_cell_commissioning Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/dual_robot_welding_cell_commissioning_start_ts 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/Documents/CoppeliaSim/exports"
WELD_CSV="$EXPORT_DIR/weld_audit.csv"
SEQ_CSV="$EXPORT_DIR/sequential_cycle.csv"
COORD_CSV="$EXPORT_DIR/coordinated_cycle.csv"
REPORT_JSON="$EXPORT_DIR/commissioning_report.json"

# Take final screenshot
take_screenshot /tmp/dual_robot_welding_cell_commissioning_end_screenshot.png

# Check if CoppeliaSim is running
APP_RUNNING=$(is_coppeliasim_running)

# ──────────────────────────────────────────────────────────────────────────────
# 1. Weld Audit CSV
# ──────────────────────────────────────────────────────────────────────────────
WELD_EXISTS=false
WELD_IS_NEW=false
WELD_ANALYSIS='{"valid": false, "row_count": 0}'

if [ -f "$WELD_CSV" ]; then
    WELD_EXISTS=true
    WELD_MTIME=$(stat -c %Y "$WELD_CSV" 2>/dev/null || echo "0")
    [ "$WELD_MTIME" -gt "$TASK_START" ] && WELD_IS_NEW=true

    WELD_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/weld_audit.csv', 'r') as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print(json.dumps({"valid": False, "row_count": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]

    def find_col(candidates):
        for c in candidates:
            for h in headers:
                if c in h:
                    return h
        return None

    rid_col = find_col(['robot_id', 'robot'])
    pid_col = find_col(['point_id', 'point'])
    err_col = find_col(['error_mm', 'error'])
    reach_col = find_col(['reachable'])

    robot_ids = set()
    max_error = 0.0
    all_reachable = True
    valid_rows = 0

    for r in rows:
        try:
            if rid_col:
                robot_ids.add(str(r.get(rid_col, '')).strip())
            if err_col:
                err = float(r[err_col])
                if err > max_error:
                    max_error = err
            if reach_col:
                rv = str(r[reach_col]).strip().lower()
                if rv not in ['1', 'true', 'yes', 't']:
                    all_reachable = False
            valid_rows += 1
        except (ValueError, KeyError):
            pass

    print(json.dumps({
        "valid": True,
        "row_count": valid_rows,
        "robot_ids": list(robot_ids),
        "num_robots": len(robot_ids),
        "max_error_mm": max_error,
        "all_reachable": all_reachable
    }))
except Exception as e:
    print(json.dumps({"valid": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
fi

# ──────────────────────────────────────────────────────────────────────────────
# 2. Sequential Cycle CSV
# ──────────────────────────────────────────────────────────────────────────────
SEQ_EXISTS=false
SEQ_IS_NEW=false
SEQ_ANALYSIS='{"valid": false, "row_count": 0}'

if [ -f "$SEQ_CSV" ]; then
    SEQ_EXISTS=true
    SEQ_MTIME=$(stat -c %Y "$SEQ_CSV" 2>/dev/null || echo "0")
    [ "$SEQ_MTIME" -gt "$TASK_START" ] && SEQ_IS_NEW=true

    SEQ_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def dist(p1, p2):
    return math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/sequential_cycle.csv', 'r') as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print(json.dumps({"valid": False, "row_count": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]

    def find_col(candidates):
        for c in candidates:
            for h in headers:
                if c in h:
                    return h
        return None

    time_col = find_col(['sim_time', 'time_s', 'time'])
    ax_col = find_col(['robot_a_ee_x', 'a_ee_x', 'r1_ee_x', 'a_x'])
    ay_col = find_col(['robot_a_ee_y', 'a_ee_y', 'r1_ee_y', 'a_y'])
    az_col = find_col(['robot_a_ee_z', 'a_ee_z', 'r1_ee_z', 'a_z'])
    bx_col = find_col(['robot_b_ee_x', 'b_ee_x', 'r2_ee_x', 'b_x'])
    by_col = find_col(['robot_b_ee_y', 'b_ee_y', 'r2_ee_y', 'b_y'])
    bz_col = find_col(['robot_b_ee_z', 'b_ee_z', 'r2_ee_z', 'b_z'])

    has_ee_cols = all([ax_col, ay_col, az_col, bx_col, by_col, bz_col])

    valid_rows = 0
    max_time = 0.0
    min_clearance = 999.0

    for r in rows:
        try:
            if time_col:
                t = float(r[time_col])
                if t > max_time:
                    max_time = t

            if has_ee_cols:
                pa = (float(r[ax_col]), float(r[ay_col]), float(r[az_col]))
                pb = (float(r[bx_col]), float(r[by_col]), float(r[bz_col]))
                d = dist(pa, pb)
                if d < min_clearance:
                    min_clearance = d

            valid_rows += 1
        except (ValueError, KeyError):
            pass

    print(json.dumps({
        "valid": True,
        "row_count": valid_rows,
        "has_ee_cols": has_ee_cols,
        "cycle_time_s": max_time,
        "min_clearance_m": min_clearance if min_clearance != 999.0 else 0.0
    }))
except Exception as e:
    print(json.dumps({"valid": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
fi

# ──────────────────────────────────────────────────────────────────────────────
# 3. Coordinated Cycle CSV
# ──────────────────────────────────────────────────────────────────────────────
COORD_EXISTS=false
COORD_IS_NEW=false
COORD_ANALYSIS='{"valid": false, "row_count": 0}'

if [ -f "$COORD_CSV" ]; then
    COORD_EXISTS=true
    COORD_MTIME=$(stat -c %Y "$COORD_CSV" 2>/dev/null || echo "0")
    [ "$COORD_MTIME" -gt "$TASK_START" ] && COORD_IS_NEW=true

    COORD_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def dist(p1, p2):
    return math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/coordinated_cycle.csv', 'r') as f:
        rows = list(csv.DictReader(f))

    if not rows:
        print(json.dumps({"valid": False, "row_count": 0}))
        sys.exit(0)

    headers = [h.strip().lower() for h in rows[0].keys()]

    def find_col(candidates):
        for c in candidates:
            for h in headers:
                if c in h:
                    return h
        return None

    time_col = find_col(['sim_time', 'time_s', 'time'])
    clearance_col = find_col(['ee_clearance', 'clearance', 'distance'])
    interlock_col = find_col(['interlock_active', 'interlock', 'paused'])
    ax_col = find_col(['robot_a_ee_x', 'a_ee_x', 'r1_ee_x', 'a_x'])
    ay_col = find_col(['robot_a_ee_y', 'a_ee_y', 'r1_ee_y', 'a_y'])
    az_col = find_col(['robot_a_ee_z', 'a_ee_z', 'r1_ee_z', 'a_z'])
    bx_col = find_col(['robot_b_ee_x', 'b_ee_x', 'r2_ee_x', 'b_x'])
    by_col = find_col(['robot_b_ee_y', 'b_ee_y', 'r2_ee_y', 'b_y'])
    bz_col = find_col(['robot_b_ee_z', 'b_ee_z', 'r2_ee_z', 'b_z'])

    has_ee_cols = all([ax_col, ay_col, az_col, bx_col, by_col, bz_col])
    has_clearance = clearance_col is not None

    valid_rows = 0
    max_time = 0.0
    min_clearance = 999.0
    interlock_count = 0
    clearance_violations = 0

    for r in rows:
        try:
            if time_col:
                t = float(r[time_col])
                if t > max_time:
                    max_time = t

            # Compute clearance from EE positions or read from column
            row_clearance = None
            if has_clearance:
                try:
                    row_clearance = float(r[clearance_col])
                except (ValueError, KeyError):
                    pass

            if row_clearance is None and has_ee_cols:
                try:
                    pa = (float(r[ax_col]), float(r[ay_col]), float(r[az_col]))
                    pb = (float(r[bx_col]), float(r[by_col]), float(r[bz_col]))
                    row_clearance = dist(pa, pb)
                except (ValueError, KeyError):
                    pass

            if row_clearance is not None:
                if row_clearance < min_clearance:
                    min_clearance = row_clearance
                if row_clearance < 0.15:
                    clearance_violations += 1

            if interlock_col:
                iv = str(r.get(interlock_col, '')).strip().lower()
                if iv in ['1', 'true', 'yes', 't']:
                    interlock_count += 1

            valid_rows += 1
        except (ValueError, KeyError):
            pass

    print(json.dumps({
        "valid": True,
        "row_count": valid_rows,
        "has_ee_cols": has_ee_cols,
        "has_clearance_col": has_clearance,
        "cycle_time_s": max_time,
        "min_clearance_m": min_clearance if min_clearance != 999.0 else 0.0,
        "clearance_violations": clearance_violations,
        "interlock_activations": interlock_count
    }))
except Exception as e:
    print(json.dumps({"valid": False, "row_count": 0, "error": str(e)}))
PYEOF
    )
fi

# ──────────────────────────────────────────────────────────────────────────────
# 4. Commissioning Report JSON
# ──────────────────────────────────────────────────────────────────────────────
REPORT_EXISTS=false
REPORT_IS_NEW=false
REPORT_ANALYSIS='{"has_fields": false}'

if [ -f "$REPORT_JSON" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_JSON" 2>/dev/null || echo "0")
    [ "$REPORT_MTIME" -gt "$TASK_START" ] && REPORT_IS_NEW=true

    REPORT_ANALYSIS=$(python3 -c "
import json
try:
    with open('$REPORT_JSON') as f:
        d = json.load(f)
    req = ['sequential_cycle_time_s', 'coordinated_cycle_time_s', 'speedup_pct',
           'min_clearance_sequential_m', 'min_clearance_coordinated_m',
           'interlock_activations', 'safety_violations',
           'total_weld_points', 'all_reachable']
    has_fields = all(k in d for k in req)

    seq_t = float(d.get('sequential_cycle_time_s', 0))
    coord_t = float(d.get('coordinated_cycle_time_s', 0))
    speedup = float(d.get('speedup_pct', 0))
    violations = int(d.get('safety_violations', -1))
    coord_faster = coord_t > 0 and seq_t > 0 and coord_t < seq_t

    print(json.dumps({
        'has_fields': has_fields,
        'sequential_cycle_time_s': seq_t,
        'coordinated_cycle_time_s': coord_t,
        'speedup_pct': speedup,
        'safety_violations': violations,
        'coordinated_faster': coord_faster
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'error': str(e)}))
" 2>/dev/null || echo '{"has_fields": false}')
fi

# ──────────────────────────────────────────────────────────────────────────────
# Write combined result JSON
# ──────────────────────────────────────────────────────────────────────────────
cat > /tmp/dual_robot_welding_cell_commissioning_result.json << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "weld_audit": {
        "exists": $WELD_EXISTS,
        "is_new": $WELD_IS_NEW,
        "analysis": $WELD_ANALYSIS
    },
    "sequential_cycle": {
        "exists": $SEQ_EXISTS,
        "is_new": $SEQ_IS_NEW,
        "analysis": $SEQ_ANALYSIS
    },
    "coordinated_cycle": {
        "exists": $COORD_EXISTS,
        "is_new": $COORD_IS_NEW,
        "analysis": $COORD_ANALYSIS
    },
    "commissioning_report": {
        "exists": $REPORT_EXISTS,
        "is_new": $REPORT_IS_NEW,
        "analysis": $REPORT_ANALYSIS
    }
}
EOF

chmod 666 /tmp/dual_robot_welding_cell_commissioning_result.json 2>/dev/null || true

echo "=== Export Complete ==="
