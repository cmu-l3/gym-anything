#!/bin/bash
echo "=== Exporting payload_torque_validation Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/payload_torque_validation_start_ts 2>/dev/null || echo "0")
RESULT_JSON="/tmp/payload_torque_validation_result.json"

# Capture final state screenshot
take_screenshot /tmp/payload_torque_validation_end_screenshot.png

# We use an inline Python script to safely parse and analyze the CSV/JSON data,
# calculate the physics integrity metrics, and dump everything cleanly to the result file.
cat << 'PYEOF' > /tmp/analyze_payload.py
import json, os, sys, csv

def calc_corr_and_intercept(x, y):
    n = len(x)
    if n < 2: return 0.0, 0.0, 0.0
    sum_x = sum(x)
    sum_y = sum(y)
    sum_x2 = sum(xi*xi for xi in x)
    sum_y2 = sum(yi*yi for yi in y)
    sum_xy = sum(xi*yi for xi, yi in zip(x, y))

    num = n * sum_xy - sum_x * sum_y
    den = ((n * sum_x2 - sum_x**2) * (n * sum_y2 - sum_y**2)) ** 0.5
    corr = num / den if den != 0 else 0.0

    denom_m = (n * sum_x2 - sum_x**2)
    m = (n * sum_xy - sum_x * sum_y) / denom_m if denom_m != 0 else 0.0
    c = (sum_y - m * sum_x) / n if n != 0 else 0.0
    return corr, m, c

def main():
    task_start = int(sys.argv[1])
    csv_path = "/home/ga/Documents/CoppeliaSim/exports/payload_torque_curve.csv"
    json_path = "/home/ga/Documents/CoppeliaSim/exports/payload_capacity_report.json"

    res = {
        "task_start": task_start,
        "csv_exists": False,
        "csv_is_new": False,
        "json_exists": False,
        "json_is_new": False,
        "csv_rows": 0,
        "correlation": 0.0,
        "torque_at_1kg": 0.0,
        "physics_valid": False,
        "flags_correct": False,
        "json_valid": False,
        "error": ""
    }

    try:
        # Check CSV
        if os.path.exists(csv_path):
            res["csv_exists"] = True
            if os.stat(csv_path).st_mtime > task_start:
                res["csv_is_new"] = True

            with open(csv_path, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)

            res["csv_rows"] = len(rows)

            if len(rows) > 0:
                headers = [h.strip().lower() for h in rows[0].keys()]
                mass_col = next((h for h in headers if 'mass' in h or 'kg' in h), None)
                torque_col = next((h for h in headers if 'torque' in h or 'nm' in h), None)
                limit_col = next((h for h in headers if 'exceed' in h or 'limit' in h), None)

                if mass_col and torque_col:
                    masses, torques = [], []
                    flags_correct = True
                    has_flags = False
                    
                    for r in rows:
                        try:
                            m = float(r[mass_col])
                            t = abs(float(r[torque_col]))
                            masses.append(m)
                            torques.append(t)
                            
                            if limit_col:
                                has_flags = True
                                flag_str = str(r[limit_col]).strip().lower()
                                flag_val = flag_str in ['1', 'true', 'yes', 'y']
                                expected_flag = t > 150.0
                                if flag_val != expected_flag:
                                    flags_correct = False
                        except Exception:
                            pass

                    res["flags_correct"] = flags_correct and has_flags

                    if len(masses) > 1:
                        corr, slope, intercept = calc_corr_and_intercept(masses, torques)
                        t_1kg = slope * 1.0 + intercept
                        
                        res["correlation"] = float(corr)
                        res["torque_at_1kg"] = float(t_1kg)

                        # Physics validation check (highly robust against spoofing)
                        if corr > 0.95 and 20.0 <= t_1kg <= 80.0:
                            res["physics_valid"] = True

        # Check JSON
        if os.path.exists(json_path):
            res["json_exists"] = True
            if os.stat(json_path).st_mtime > task_start:
                res["json_is_new"] = True

            with open(json_path, 'r') as f:
                jdata = json.load(f)

            req = ['total_tests', 'max_safe_mass_kg', 'limit_nm', 'peak_torque_nm']
            if all(k in jdata for k in req):
                # Ensure the recorded limit is correct
                if abs(float(jdata.get('limit_nm', 0)) - 150.0) < 0.1:
                    res["json_valid"] = True

    except Exception as e:
        res["error"] = str(e)

    with open('/tmp/payload_torque_validation_result.json', 'w') as f:
        json.dump(res, f)

if __name__ == "__main__":
    main()
PYEOF

# Execute the analysis script safely
python3 /tmp/analyze_payload.py "$TASK_START"

# Fix permissions so the framework can easily retrieve it
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="