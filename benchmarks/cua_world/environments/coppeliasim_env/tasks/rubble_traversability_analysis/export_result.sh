#!/bin/bash
echo "=== Exporting rubble_traversability_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/rubble_traversability_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/traversability_timeseries.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/traversability_report.json"

# Take final screenshot
take_screenshot /tmp/rubble_traversability_end_screenshot.png

# Initial existence and timestamp checks
CSV_EXISTS=false
CSV_IS_NEW=false
if [ -f "$CSV" ]; then
    CSV_EXISTS=true
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    [ "$CSV_MTIME" -gt "$TASK_START" ] && CSV_IS_NEW=true
fi

JSON_EXISTS=false
JSON_IS_NEW=false
if [ -f "$JSON" ]; then
    JSON_EXISTS=true
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    [ "$JSON_MTIME" -gt "$TASK_START" ] && JSON_IS_NEW=true
fi

# Run Python data parser and metrics validation
CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

def variance(data):
    if len(data) < 2: return 0.0
    mean = sum(data) / len(data)
    return sum((x - mean) ** 2 for x in data) / (len(data) - 1)

def find_col(headers, candidates):
    hl = [h.strip().lower() for h in headers]
    for c in candidates:
        if c in hl: return headers[hl.index(c)]
    return None

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/traversability_timeseries.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    
    if not rows:
        print(json.dumps({"has_required_cols": False, "num_trials": 0}))
        sys.exit(0)
        
    headers = list(rows[0].keys())
    
    col_trial = find_col(headers, ['trial_id', 'trial'])
    col_scale = find_col(headers, ['debris_scale_m', 'scale_m', 'scale'])
    col_time = find_col(headers, ['time_s', 'time', 'sim_time'])
    col_roll = find_col(headers, ['roll_deg', 'roll'])
    col_pitch = find_col(headers, ['pitch_deg', 'pitch'])
    
    has_cols = all([col_trial, col_scale, col_time, col_roll, col_pitch])
    
    stats = {
        "has_required_cols": has_cols,
        "num_trials": 0,
        "increasing_scale": False,
        "all_trials_5s": False,
        "variance_ok": False,
        "total_rows": len(rows)
    }
    
    if has_cols:
        trials = {}
        for r in rows:
            tid = r[col_trial]
            if tid not in trials:
                trials[tid] = {'times': [], 'scales': [], 'rolls': [], 'pitches': []}
            try:
                trials[tid]['times'].append(float(r[col_time]))
                trials[tid]['scales'].append(float(r[col_scale]))
                trials[tid]['rolls'].append(float(r[col_roll]))
                trials[tid]['pitches'].append(float(r[col_pitch]))
            except ValueError:
                pass
        
        stats["num_trials"] = len(trials)
        
        # Check trial durations
        durations_ok = 0
        variances_ok = 0
        scales = []
        
        for tid, data in trials.items():
            if not data['times']: continue
            duration = max(data['times']) - min(data['times'])
            if duration >= 4.8:  # Allow slight tolerance
                durations_ok += 1
            
            # Use max scale of the trial representing its scale
            scales.append(max(data['scales']))
            
            var_r = variance(data['rolls'])
            var_p = variance(data['pitches'])
            if var_r > 0.001 or var_p > 0.001:  # Non-trivial physics interaction
                variances_ok += 1
        
        if stats["num_trials"] > 0:
            stats["all_trials_5s"] = (durations_ok == stats["num_trials"])
            stats["variance_ok"] = (variances_ok == stats["num_trials"])
            
            # Check increasing scale constraint
            if len(scales) >= 3:
                is_increasing = all(scales[i] < scales[i+1] for i in range(len(scales)-1))
                stats["increasing_scale"] = is_increasing

    print(json.dumps(stats))

except Exception as e:
    print(json.dumps({"has_required_cols": False, "num_trials": 0, "error": str(e)}))
PYEOF
)

JSON_ANALYSIS=$(python3 << 'PYEOF'
import json, sys
try:
    with open('/home/ga/Documents/CoppeliaSim/exports/traversability_report.json') as f:
        data = json.load(f)
        
    req_keys = ['total_trials', 'debris_objects_per_trial', 'max_tilt_by_trial', 'tipped_trials', 'max_safe_debris_scale_m']
    has_fields = all(k in data for k in req_keys)
    
    print(json.dumps({
        "has_fields": has_fields,
        "total_trials": int(data.get('total_trials', 0)),
        "debris_objects": int(data.get('debris_objects_per_trial', 0)),
        "tipped_trials_count": len(data.get('tipped_trials', []))
    }))
except Exception as e:
    print(json.dumps({"has_fields": False, "error": str(e)}))
PYEOF
)

# Compile results
cat > /tmp/rubble_traversability_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": ${CSV_ANALYSIS:-{"has_required_cols": false}},
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_analysis": ${JSON_ANALYSIS:-{"has_fields": false}}
}
EOF

echo "=== Export Complete ==="