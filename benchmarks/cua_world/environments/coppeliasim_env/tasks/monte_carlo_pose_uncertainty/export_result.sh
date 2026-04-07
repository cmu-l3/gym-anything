#!/bin/bash
echo "=== Exporting monte_carlo_pose_uncertainty Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/mc_uncertainty_start_ts 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/mc_uncertainty_end_screenshot.png

# Run Python evaluation script INSIDE the container to check kinematics against the active CoppeliaSim engine
echo "Running kinematic cross-check..."
python3 << PYEOF
import sys, json, csv, math, random, os
import numpy as np

result = {
    "csv_exists": False,
    "csv_is_new": False,
    "row_count": 0,
    "unique_configs": 0,
    "noise_std_dev": 0.0,
    "json_valid": False,
    "kinematic_check_passed": False,
    "max_kinematic_error_mm": 9999.0,
    "error_msg": ""
}

try:
    task_start = $TASK_START
    csv_path = "/home/ga/Documents/CoppeliaSim/exports/mc_samples.csv"
    json_path = "/home/ga/Documents/CoppeliaSim/exports/uncertainty_report.json"

    # 1. File existence and timestamps
    if os.path.exists(csv_path):
        result["csv_exists"] = True
        if os.path.getmtime(csv_path) > task_start:
            result["csv_is_new"] = True

    if not result["csv_exists"] or not os.path.exists(json_path):
        raise Exception("Required output files not found")

    # 2. Parse JSON
    with open(json_path, 'r') as f:
        report = json.load(f)
    
    joint_names = report.get("joint_names", [])
    ee_name = report.get("end_effector_name", "")
    result["json_valid"] = True

    # 3. Parse CSV and compute noise stats
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    result["row_count"] = len(rows)

    diffs = []
    configs = set()
    for r in rows:
        configs.add(r.get('config_id'))
        for i in range(1, 7):
            try:
                nom = float(r.get(f'nom_j{i}', 0))
                noisy = float(r.get(f'noisy_j{i}', 0))
                diffs.append(noisy - nom)
            except:
                pass

    result["unique_configs"] = len(configs)
    if len(diffs) > 0:
        result["noise_std_dev"] = float(np.std(diffs))

    # 4. Kinematic Ground-Truth Cross-Check (Anti-Gaming)
    if len(rows) > 0 and len(joint_names) == 6 and ee_name:
        sys.path.insert(0, '/opt/CoppeliaSim/programming/zmqRemoteApi/clients/python/src')
        from coppeliasim_zmqremoteapi_client import RemoteAPIClient
        client = RemoteAPIClient()
        sim = client.require('sim')

        j_handles = [sim.getObject(name) for name in joint_names]
        ee_handle = sim.getObject(ee_name)

        # Sample up to 10 rows randomly to verify math
        sample_rows = random.sample(rows, min(10, len(rows)))
        max_err = 0.0

        for r in sample_rows:
            # Set joints to the noisy configuration
            for i in range(6):
                sim.setJointPosition(j_handles[i], float(r[f'noisy_j{i+1}']))
            
            # Read simulator ground truth position
            pos = sim.getObjectPosition(ee_handle, -1)
            
            # Agent's reported position
            ex = float(r['ee_x'])
            ey = float(r['ee_y'])
            ez = float(r['ee_z'])
            
            # Euclidean distance error between simulation and agent's report
            dist = math.sqrt((pos[0]-ex)**2 + (pos[1]-ey)**2 + (pos[2]-ez)**2) * 1000.0 # to mm
            if dist > max_err:
                max_err = dist

        result["max_kinematic_error_mm"] = max_err
        # If the error is less than 0.5 mm, the agent actually used the kinematic model
        if max_err < 0.5:
            result["kinematic_check_passed"] = True
        else:
            result["error_msg"] = f"Kinematic mismatch: max error {max_err:.2f} mm exceeds 0.5 mm tolerance"
    else:
        result["error_msg"] = "Missing joint/EE names in JSON or CSV is empty"

except Exception as e:
    result["error_msg"] = str(e)

# Write result to temp file
with open('/tmp/mc_uncertainty_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

echo "Cross-check complete."
cat /tmp/mc_uncertainty_result.json
echo ""
echo "=== Export Complete ==="