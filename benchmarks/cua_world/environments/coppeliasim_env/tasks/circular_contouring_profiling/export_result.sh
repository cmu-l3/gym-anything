#!/bin/bash
echo "=== Exporting circular_contouring_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/circular_contouring_profiling_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/contouring_data.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/contouring_report.json"

# Capture final screenshot
take_screenshot /tmp/circular_contouring_profiling_end_screenshot.png

# Initialize flags
CSV_EXISTS="false"
CSV_IS_NEW="false"
JSON_EXISTS="false"
JSON_IS_NEW="false"

# Analyze CSV using an inline Python script
CSV_ANALYSIS='{"valid": false}'
if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys, math

def get_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl:
            return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/contouring_data.csv', 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print(json.dumps({"valid": False, "reason": "empty"}))
        sys.exit(0)

    headers = list(rows[0].keys())
    id_col = get_col(headers, ['speed_profile_id', 'profile_id', 'run_id', 'speed'])
    t_col = get_col(headers, ['sim_time_s', 'time_s', 'time'])
    ax_col = get_col(headers, ['actual_x', 'ax', 'measured_x', 'x'])
    ay_col = get_col(headers, ['actual_y', 'ay', 'measured_y', 'y'])
    err_col = get_col(headers, ['radial_error_mm', 'error_mm', 'error'])

    if not (id_col and t_col and ax_col and ay_col and err_col):
        print(json.dumps({"valid": False, "reason": "missing_columns"}))
        sys.exit(0)

    # Group data by run ID
    runs = {}
    for r in rows:
        rid = r.get(id_col, 'unknown')
        if rid not in runs:
            runs[rid] = []
        try:
            runs[rid].append({
                't': float(r[t_col]),
                'ax': float(r[ax_col]),
                'ay': float(r[ay_col]),
                'err': float(r[err_col])
            })
        except ValueError:
            pass

    # Process stats for each run
    run_stats = []
    for rid, data in runs.items():
        if len(data) < 10:
            continue
        times = [d['t'] for d in data]
        errs = [d['err'] for d in data]
        axs = [d['ax'] for d in data]
        ays = [d['ay'] for d in data]

        duration = max(times) - min(times)
        max_err = max(errs)
        mean_err = sum(errs) / len(errs) if len(errs) > 0 else 0
        span_x = max(axs) - min(axs)
        span_y = max(ays) - min(ays)

        run_stats.append({
            'id': rid,
            'samples': len(data),
            'duration': duration,
            'max_err': max_err,
            'mean_err': mean_err,
            'span_x': span_x,
            'span_y': span_y
        })

    if len(run_stats) >= 2:
        # Determine the fastest (shortest duration) and slowest (longest duration) runs
        slowest = max(run_stats, key=lambda x: x['duration'])
        fastest = min(run_stats, key=lambda x: x['duration'])
        # Physics lag implies the fastest run cuts corners more, increasing the radial error
        physics_lag_verified = (fastest['mean_err'] > slowest['mean_err'] * 1.05) or (fastest['max_err'] > slowest['max_err'] * 1.05)
    else:
        physics_lag_verified = False

    print(json.dumps({
        "valid": True,
        "total_runs": len(run_stats),
        "min_samples_per_run": min([r['samples'] for r in run_stats]) if run_stats else 0,
        "max_span_x": max([r['span_x'] for r in run_stats]) if run_stats else 0.0,
        "max_span_y": max([r['span_y'] for r in run_stats]) if run_stats else 0.0,
        "physics_lag_verified": physics_lag_verified,
        "fastest_mean_err": fastest['mean_err'] if len(run_stats) >= 2 else 0.0,
        "slowest_mean_err": slowest['mean_err'] if len(run_stats) >= 2 else 0.0
    }))
except Exception as e:
    print(json.dumps({"valid": False, "error": str(e)}))
PYEOF
    )
fi

# Analyze JSON report
JSON_ANALYSIS='{"valid": false}'
if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_ANALYSIS=$(python3 -c "
import json
try:
    with open('$JSON', 'r') as f:
        d = json.load(f)
    req = ['total_runs', 'speeds_tested', 'max_error_slowest_run_mm', 'max_error_fastest_run_mm', 'physics_lag_detected']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'valid': has_fields,
        'total_runs': int(d.get('total_runs', 0)),
        'lag_detected': bool(d.get('physics_lag_detected', False))
    }))
except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
" 2>/dev/null || echo '{"valid": false}')
fi

# Consolidate results into a single JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_analysis": $JSON_ANALYSIS
}
EOF

# Ensure safe copying
rm -f /tmp/circular_contouring_result.json 2>/dev/null || sudo rm -f /tmp/circular_contouring_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/circular_contouring_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/circular_contouring_result.json
chmod 666 /tmp/circular_contouring_result.json 2>/dev/null || sudo chmod 666 /tmp/circular_contouring_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="