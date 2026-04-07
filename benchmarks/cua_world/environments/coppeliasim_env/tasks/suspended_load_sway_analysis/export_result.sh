#!/bin/bash
echo "=== Exporting suspended_load_sway_analysis Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/suspended_load_sway_analysis_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/sway_timeseries.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/sway_report.json"

# Take final screenshot
take_screenshot /tmp/suspended_load_sway_analysis_end_screenshot.png

CSV_EXISTS="false"
CSV_IS_NEW="false"
CSV_ANALYSIS='{"has_data": false, "has_abrupt": false, "has_smooth": false, "reached_target": false, "abrupt_max_sway": 0.0, "smooth_max_sway": 0.0, "period_estimate": 0.0}'

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi

    # Parse the CSV to verify physics, bounds, and trial existence
    CSV_ANALYSIS=$(python3 << 'PYEOF'
import csv, json, sys

try:
    with open('/home/ga/Documents/CoppeliaSim/exports/sway_timeseries.csv') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        print(json.dumps({"has_data": False, "has_abrupt": False, "has_smooth": False, "reached_target": False, "abrupt_max_sway": 0.0, "smooth_max_sway": 0.0, "period_estimate": 0.0}))
        sys.exit(0)

    # Separate by trial
    trials = {}
    for r in rows:
        trial = r.get('trial_name', '').strip().lower()
        if not trial:
            continue
        if trial not in trials:
            trials[trial] = {'time': [], 'x': [], 'angle': []}
        try:
            trials[trial]['time'].append(float(r['sim_time_s']))
            trials[trial]['x'].append(float(r['trolley_x_m']))
            trials[trial]['angle'].append(float(r['sway_angle_deg']))
        except:
            pass

    has_abrupt = 'abrupt' in trials and len(trials['abrupt']['time']) >= 50
    has_smooth = 'smooth' in trials and len(trials['smooth']['time']) >= 50

    reached_target = False
    abrupt_max = 0.0
    smooth_max = 0.0
    period_estimate = 0.0

    if has_abrupt:
        x_max = max(trials['abrupt']['x'])
        if x_max >= 1.9:
            reached_target = True
        abrupt_max = max(abs(a) for a in trials['abrupt']['angle'])

        # PHYSICS CHECK: Estimate pendulum oscillation period from residual sway
        residual_times = []
        residual_angles = []
        for t, x, a in zip(trials['abrupt']['time'], trials['abrupt']['x'], trials['abrupt']['angle']):
            if x >= 1.9:  # Trolley reached the end, look at free-swing
                residual_times.append(t)
                residual_angles.append(a)

        if len(residual_times) > 20:
            mean_a = sum(residual_angles) / len(residual_angles)
            crossings = []
            for i in range(1, len(residual_angles)):
                if (residual_angles[i-1] - mean_a) * (residual_angles[i] - mean_a) < 0:
                    # Linear interpolation for accurate crossing time
                    t1, t2 = residual_times[i-1], residual_times[i]
                    a1, a2 = residual_angles[i-1] - mean_a, residual_angles[i] - mean_a
                    if a2 - a1 != 0:
                        t_cross = t1 - a1 * (t2 - t1) / (a2 - a1)
                        crossings.append(t_cross)

            # A full period occurs between every second zero-crossing
            if len(crossings) >= 3:
                periods = []
                for i in range(2, len(crossings)):
                    periods.append(crossings[i] - crossings[i-2])
                period_estimate = sum(periods) / len(periods)

    if has_smooth:
        smooth_max = max(abs(a) for a in trials['smooth']['angle'])
        if max(trials['smooth']['x']) < 1.9:
            reached_target = False  # Both trials must reach the target

    print(json.dumps({
        "has_data": True,
        "has_abrupt": has_abrupt,
        "has_smooth": has_smooth,
        "reached_target": reached_target,
        "abrupt_max_sway": abrupt_max,
        "smooth_max_sway": smooth_max,
        "period_estimate": period_estimate
    }))

except Exception as e:
    print(json.dumps({
        "has_data": False, "has_abrupt": False, "has_smooth": False,
        "reached_target": False, "abrupt_max_sway": 0.0,
        "smooth_max_sway": 0.0, "period_estimate": 0.0, "error": str(e)
    }))
PYEOF
    )
fi

JSON_EXISTS="false"
JSON_IS_NEW="false"
JSON_FIELDS='{"has_fields": false, "pendulum_length_m": 0.0, "abrupt_max": 0.0, "smooth_max": 0.0, "reduction_pct": 0.0}'

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi

    JSON_FIELDS=$(python3 -c "
import json, sys
try:
    with open('$JSON') as f:
        d = json.load(f)
    req = ['pendulum_length_m', 'abrupt_max_sway_deg', 'smooth_max_sway_deg', 'sway_reduction_pct']
    has_fields = all(k in d for k in req)
    print(json.dumps({
        'has_fields': has_fields,
        'pendulum_length_m': float(d.get('pendulum_length_m', 0.0)),
        'abrupt_max': float(d.get('abrupt_max_sway_deg', 0.0)),
        'smooth_max': float(d.get('smooth_max_sway_deg', 0.0)),
        'reduction_pct': float(d.get('sway_reduction_pct', 0.0))
    }))
except Exception as e:
    print(json.dumps({'has_fields': False, 'pendulum_length_m': 0.0, 'abrupt_max': 0.0, 'smooth_max': 0.0, 'reduction_pct': 0.0}))
" 2>/dev/null || echo '{"has_fields": false, "pendulum_length_m": 0.0, "abrupt_max": 0.0, "smooth_max": 0.0, "reduction_pct": 0.0}')
fi

# Bundle results into JSON
cat > /tmp/sway_analysis_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_analysis": $CSV_ANALYSIS,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW,
    "json_fields": $JSON_FIELDS
}
EOF

echo "=== Export Complete ==="