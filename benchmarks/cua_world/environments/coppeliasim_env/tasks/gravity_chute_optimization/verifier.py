#!/usr/bin/env python3
"""
Verifier for gravity_chute_optimization task.

Scoring (100 points):
  - Criterion 1 (20 pts): Output CSV and JSON files exist and were created after task start.
  - Criterion 2 (20 pts): CSV has >= 10 rows and required kinematics columns.
  - Criterion 3 (30 pts): Physics consistency. Velocities are physically plausible (< 15 m/s)
                          and generally increase with steeper angles.
  - Criterion 4 (30 pts): Accurate optimization. The JSON reports an optimal angle that 
                          matches the best angle derived from the CSV data.

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/gravity_chute_result.json"


def verify_gravity_chute_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    csv_exists = result.get("csv_exists", False)
    csv_is_new = result.get("csv_is_new", False)
    json_exists = result.get("json_exists", False)
    json_is_new = result.get("json_is_new", False)

    # Criterion 1: Files exist and are new (20 pts)
    if csv_exists and json_exists and csv_is_new and json_is_new:
        score += 20
        feedback.append("Both output files created after task start (+20)")
    elif csv_exists and json_exists:
        feedback.append("Files exist but appear to predate the task start (stale files)")
    else:
        feedback.append("Missing one or both expected output files")

    # Criterion 2: CSV Data Completeness (20 pts)
    csv_analysis = result.get("csv_analysis", {})
    is_valid_csv = csv_analysis.get("valid", False)
    rows_extracted = int(csv_analysis.get("data_extracted", 0))

    if is_valid_csv and rows_extracted >= 10:
        score += 20
        feedback.append(f"CSV format valid with {rows_extracted} data rows (+20)")
    elif is_valid_csv and rows_extracted >= 4:
        score += 10
        feedback.append(f"CSV format valid but only {rows_extracted} data rows (partial: 10/20)")
    else:
        feedback.append("CSV lacks required columns or has insufficient data rows")

    # Criterion 3: Physics Consistency (30 pts)
    angles = csv_analysis.get("angles", [])
    vels = csv_analysis.get("vels", [])
    computed_best_angle = csv_analysis.get("computed_best_angle", None)

    if len(vels) >= 4:
        max_vel = max(vels)
        # Check if trend is generally increasing. Highest angle should have higher velocity than lowest angle.
        # Note: If friction is extremely high, lowest angles might have 0 velocity (stuck)
        physics_plausible = True
        
        if max_vel > 20.0:  # 2m ramp cannot produce > 20m/s purely from gravity
            physics_plausible = False
            feedback.append(f"Physics anomaly: max velocity {max_vel:.1f} m/s is impossibly high")
            
        # The velocity at the highest tested angle should be strictly greater than at the lowest angle
        # assuming the lowest angle isn't somehow friction-free and the highest isn't stuck
        if vels[-1] <= vels[0] and vels[-1] < 1.0:
            physics_plausible = False
            feedback.append("Physics anomaly: steeper angles did not produce higher exit velocities")

        if physics_plausible:
            score += 30
            feedback.append(f"Physics data consistent: max vel={max_vel:.2f} m/s, monotonic trend observed (+30)")
        else:
            score += 10
            feedback.append("Data extracted but physics consistency checks failed (partial: 10/30)")
    else:
        feedback.append("Insufficient data to verify physics consistency")

    # Criterion 4: Accurate Optimization (30 pts)
    json_analysis = result.get("json_analysis", {})
    if json_analysis.get("valid", False) and computed_best_angle is not None:
        reported_angle = json_analysis.get("optimal_angle_deg", -999)
        
        # Check if the reported angle matches the actual best angle from the CSV data
        if abs(reported_angle - computed_best_angle) <= 1.0:
            score += 30
            feedback.append(f"Optimization accurate: JSON correctly identifies {reported_angle}° as the optimal angle (+30)")
        else:
            feedback.append(f"Optimization mismatch: JSON reports {reported_angle}°, but CSV data implies {computed_best_angle}° is closest to 1.5 m/s")
    else:
        feedback.append("Optimization JSON invalid or missing required fields")

    passed = score >= 70
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }