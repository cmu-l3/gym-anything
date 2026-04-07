#!/bin/bash
echo "=== Exporting digital_twin_calibration Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/digital_twin_calibration_start_ts 2>/dev/null || echo "0")
RESULT_JSON="/tmp/digital_twin_calibration_result.json"

# Capture final state screenshot
take_screenshot /tmp/digital_twin_calibration_end_screenshot.png

# Use an inline Python script to safely parse and analyze all output files
cat << 'PYEOF' > /tmp/analyze_digital_twin.py
import json, os, sys, csv

def main():
    task_start = int(sys.argv[1])

    EXPORTS = "/home/ga/Documents/CoppeliaSim/exports"
    kin_csv   = os.path.join(EXPORTS, "kinematic_survey.csv")
    dyn_csv   = os.path.join(EXPORTS, "dynamic_excitation.csv")
    par_json  = os.path.join(EXPORTS, "identified_parameters.json")
    val_csv   = os.path.join(EXPORTS, "validation_results.csv")
    rep_json  = os.path.join(EXPORTS, "characterization_report.json")

    res = {
        "task_start": task_start,
        # kinematic_survey.csv
        "kin_csv_exists": False,
        "kin_csv_is_new": False,
        "kin_csv_rows": 0,
        "kin_csv_has_required_cols": False,
        "kin_csv_repeatability_rows": 0,
        "kin_csv_unique_configs": 0,
        "kin_csv_tcp_span_x": 0.0,
        "kin_csv_tcp_span_y": 0.0,
        "kin_csv_tcp_span_z": 0.0,
        # dynamic_excitation.csv
        "dyn_csv_exists": False,
        "dyn_csv_is_new": False,
        "dyn_csv_rows": 0,
        "dyn_csv_has_required_cols": False,
        "dyn_csv_distinct_joints": 0,
        "dyn_csv_time_range_s": 0.0,
        "dyn_csv_has_nonzero_torque": False,
        # identified_parameters.json
        "par_json_exists": False,
        "par_json_is_new": False,
        "par_json_joint_count": 0,
        "par_json_all_inertia_positive": False,
        "par_json_all_r2_valid": False,
        # validation_results.csv
        "val_csv_exists": False,
        "val_csv_is_new": False,
        "val_csv_rows": 0,
        "val_csv_has_pred_and_meas": False,
        # characterization_report.json
        "rep_json_exists": False,
        "rep_json_is_new": False,
        "rep_json_has_kinematic": False,
        "rep_json_has_dynamic": False,
        "rep_json_has_validation": False,
        "error": ""
    }

    try:
        # ===== kinematic_survey.csv =====
        if os.path.exists(kin_csv):
            res["kin_csv_exists"] = True
            if os.stat(kin_csv).st_mtime > task_start:
                res["kin_csv_is_new"] = True
            with open(kin_csv, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
            res["kin_csv_rows"] = len(rows)
            if len(rows) > 0:
                hdrs = [h.strip().lower() for h in rows[0].keys()]
                # Check for joint angle and tcp columns
                has_joints = sum(1 for h in hdrs if h.startswith('j') and 'rad' in h) >= 6
                has_tcp = sum(1 for h in hdrs if h.startswith('tcp_') or h in ['tcp_x','tcp_y','tcp_z','x','y','z']) >= 3
                res["kin_csv_has_required_cols"] = has_joints or has_tcp or len(hdrs) >= 8

                # Count repeatability rows
                rep_col = next((h for h in rows[0].keys() if 'repeat' in h.lower()), None)
                if rep_col:
                    res["kin_csv_repeatability_rows"] = sum(
                        1 for r in rows
                        if str(r.get(rep_col, '')).strip().lower() in ['1', 'true', 'yes']
                    )

                # Measure spatial diversity of TCP positions
                tcp_x_col = next((h for h in rows[0].keys() if 'tcp_x' in h.lower() or h.lower() == 'x'), None)
                tcp_y_col = next((h for h in rows[0].keys() if 'tcp_y' in h.lower() or h.lower() == 'y'), None)
                tcp_z_col = next((h for h in rows[0].keys() if 'tcp_z' in h.lower() or h.lower() == 'z'), None)
                if tcp_x_col and tcp_y_col and tcp_z_col:
                    xs, ys, zs = [], [], []
                    for r in rows:
                        try:
                            xs.append(float(r[tcp_x_col]))
                            ys.append(float(r[tcp_y_col]))
                            zs.append(float(r[tcp_z_col]))
                        except (ValueError, TypeError):
                            pass
                    if xs:
                        res["kin_csv_tcp_span_x"] = max(xs) - min(xs)
                        res["kin_csv_tcp_span_y"] = max(ys) - min(ys)
                        res["kin_csv_tcp_span_z"] = max(zs) - min(zs)

                # Count unique configs (based on joint angles rounded to 0.01 rad)
                seen = set()
                for r in rows:
                    key_parts = []
                    for h in sorted(rows[0].keys()):
                        if 'rad' in h.lower() and h.lower().startswith('j'):
                            try:
                                key_parts.append(round(float(r[h]), 2))
                            except (ValueError, TypeError):
                                pass
                    if key_parts:
                        seen.add(tuple(key_parts))
                res["kin_csv_unique_configs"] = len(seen)

        # ===== dynamic_excitation.csv =====
        if os.path.exists(dyn_csv):
            res["dyn_csv_exists"] = True
            if os.stat(dyn_csv).st_mtime > task_start:
                res["dyn_csv_is_new"] = True
            with open(dyn_csv, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
            res["dyn_csv_rows"] = len(rows)
            if len(rows) > 0:
                hdrs_lower = [h.strip().lower() for h in rows[0].keys()]
                has_joint_id = any('joint' in h for h in hdrs_lower)
                has_time = any('time' in h for h in hdrs_lower)
                has_torque = any('torque' in h for h in hdrs_lower)
                res["dyn_csv_has_required_cols"] = has_joint_id and has_time and has_torque

                # Count distinct joint IDs
                jid_col = next((h for h in rows[0].keys() if 'joint' in h.lower() and 'id' in h.lower()), None)
                if not jid_col:
                    jid_col = next((h for h in rows[0].keys() if 'joint' in h.lower()), None)
                if jid_col:
                    joint_ids = set()
                    for r in rows:
                        try:
                            joint_ids.add(str(r[jid_col]).strip())
                        except Exception:
                            pass
                    res["dyn_csv_distinct_joints"] = len(joint_ids)

                # Time range
                time_col = next((h for h in rows[0].keys() if 'time' in h.lower()), None)
                if time_col:
                    times = []
                    for r in rows:
                        try:
                            times.append(float(r[time_col]))
                        except (ValueError, TypeError):
                            pass
                    if times:
                        res["dyn_csv_time_range_s"] = max(times) - min(times)

                # Non-zero torque check
                torque_col = next((h for h in rows[0].keys() if 'torque' in h.lower()), None)
                if torque_col:
                    nonzero = 0
                    for r in rows:
                        try:
                            if abs(float(r[torque_col])) > 1e-6:
                                nonzero += 1
                        except (ValueError, TypeError):
                            pass
                    res["dyn_csv_has_nonzero_torque"] = nonzero > len(rows) * 0.1

        # ===== identified_parameters.json =====
        if os.path.exists(par_json):
            res["par_json_exists"] = True
            if os.stat(par_json).st_mtime > task_start:
                res["par_json_is_new"] = True
            with open(par_json, 'r') as f:
                pdata = json.load(f)
            joints_list = pdata.get("joints", [])
            if not isinstance(joints_list, list):
                joints_list = []
            res["par_json_joint_count"] = len(joints_list)

            if len(joints_list) >= 6:
                all_pos = True
                all_r2 = True
                for j in joints_list[:6]:
                    inertia = j.get("inertia_kg_m2", j.get("inertia", 0))
                    r2 = j.get("r_squared", j.get("r2", -1))
                    if not isinstance(inertia, (int, float)) or inertia <= 0:
                        all_pos = False
                    if not isinstance(r2, (int, float)) or r2 < 0 or r2 > 1:
                        all_r2 = False
                res["par_json_all_inertia_positive"] = all_pos
                res["par_json_all_r2_valid"] = all_r2

        # ===== validation_results.csv =====
        if os.path.exists(val_csv):
            res["val_csv_exists"] = True
            if os.stat(val_csv).st_mtime > task_start:
                res["val_csv_is_new"] = True
            with open(val_csv, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
            res["val_csv_rows"] = len(rows)
            if len(rows) > 0:
                hdrs_lower = [h.strip().lower() for h in rows[0].keys()]
                has_pred = any('pred' in h for h in hdrs_lower)
                has_meas = any('meas' in h for h in hdrs_lower)
                res["val_csv_has_pred_and_meas"] = has_pred and has_meas

        # ===== characterization_report.json =====
        if os.path.exists(rep_json):
            res["rep_json_exists"] = True
            if os.stat(rep_json).st_mtime > task_start:
                res["rep_json_is_new"] = True
            with open(rep_json, 'r') as f:
                rdata = json.load(f)
            res["rep_json_has_kinematic"] = "kinematic" in rdata and isinstance(rdata["kinematic"], dict)
            res["rep_json_has_dynamic"] = "dynamic" in rdata and isinstance(rdata["dynamic"], dict)
            res["rep_json_has_validation"] = "validation" in rdata and isinstance(rdata["validation"], dict)

    except Exception as e:
        res["error"] = str(e)

    with open('/tmp/digital_twin_calibration_result.json', 'w') as f:
        json.dump(res, f)

if __name__ == "__main__":
    main()
PYEOF

# Execute the analysis script safely
python3 /tmp/analyze_digital_twin.py "$TASK_START"

# Fix permissions so the framework can easily retrieve it
chmod 666 "$RESULT_JSON"

echo "=== Export Complete ==="
