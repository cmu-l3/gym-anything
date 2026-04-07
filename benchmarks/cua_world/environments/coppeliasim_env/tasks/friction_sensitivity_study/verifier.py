#!/usr/bin/env python3
"""
Verifier for friction_sensitivity_study task.

Verifies that the agent properly built the simulation environment,
ran trials varying the friction coefficient, and exported valid data
that obeys expected physics properties (higher friction = less sliding).
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_friction_sensitivity_study(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not complete."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # Criterion 1: CSV exists and is new (15 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 15
        feedback.append("CSV file created after task start (+15)")
    elif result.get("csv_exists"):
        feedback.append("CSV file exists but is stale (predates task start)")
    else:
        feedback.append("friction_sweep.csv not found")

    # Criterion 2: CSV has >= 8 rows (20 pts)
    row_count = result.get("csv_row_count", 0)
    if row_count >= 8:
        score += 20
        feedback.append(f"CSV has {row_count} trials (>= 8 required) (+20)")
    elif row_count >= 4:
        score += 10
        feedback.append(f"CSV has {row_count} trials (partial: 10/20)")
    else:
        feedback.append(f"CSV has only {row_count} trials (need >= 8)")

    # Data arrays from CSV
    frictions = result.get("frictions", [])
    distances = result.get("distances", [])
    valid_pairs = len(frictions)

    # Criterion 3: Valid friction range (15 pts)
    if result.get("has_fric_col") and valid_pairs >= 6:
        fric_span = max(frictions) - min(frictions)
        if fric_span >= 0.3:
            score += 15
            feedback.append(f"Tested valid friction range: {min(frictions):.2f} to {max(frictions):.2f} (+15)")
        elif fric_span > 0.05:
            score += 7
            feedback.append(f"Friction range too narrow: {fric_span:.2f} (partial: 7/15)")
        else:
            feedback.append("Friction values did not vary significantly")
    else:
        feedback.append("CSV lacks valid friction_coeff column or sufficient values")

    # Criterion 4: Valid slide distances (15 pts)
    if result.get("has_dist_col") and valid_pairs >= 6:
        dist_span = max(distances) - min(distances)
        if dist_span > 0.01 and max(distances) > 0.05:
            score += 15
            feedback.append(f"Valid slide distance variation observed: max={max(distances):.2f}m (+15)")
        else:
            feedback.append(f"Slide distances did not vary or were near zero (max={max(distances) if distances else 0}:.2f) - did block move?")
    else:
        feedback.append("CSV lacks valid slide_distance_m column or sufficient values")

    # Criterion 5: Physical Plausibility (5 pts)
    # Higher friction should result in shorter slide distances
    if valid_pairs >= 4 and max(distances) > min(distances):
        # Sort distance by friction (ascending)
        fric_dist = sorted(zip(frictions, distances), key=lambda x: x[0])
        half = len(fric_dist) // 2
        
        mean_low_fric_dist = sum(x[1] for x in fric_dist[:half]) / half
        mean_high_fric_dist = sum(x[1] for x in fric_dist[-half:]) / half
        
        if mean_low_fric_dist > mean_high_fric_dist * 1.05:
            score += 5
            feedback.append("Physically plausible data trend: higher friction = less sliding (+5)")
        else:
            feedback.append(f"Data defies expected physics: low friction avg dist ({mean_low_fric_dist:.2f}m) not strictly > high friction dist ({mean_high_fric_dist:.2f}m)")
    else:
        feedback.append("Not enough varied data to test physical plausibility")

    # Criterion 6: JSON Report Exists (10 pts)
    if result.get("json_exists") and result.get("json_is_new"):
        score += 10
        feedback.append("JSON report created after task start (+10)")
    elif result.get("json_exists"):
        feedback.append("JSON report exists but is stale")
    else:
        feedback.append("friction_report.json not found")

    # Criterion 7: JSON Report Valid (20 pts)
    if result.get("json_fields_valid"):
        t_trials = result.get("total_trials", 0)
        f_min = result.get("fric_min", 0.0)
        f_max = result.get("fric_max", 0.0)
        
        if t_trials >= 8 and f_min < f_max:
            score += 20
            feedback.append(f"JSON summary valid: {t_trials} trials reported (+20)")
        else:
            score += 10
            feedback.append(f"JSON summary contains fields but data is suspicious (trials={t_trials}, f_min={f_min}, f_max={f_max}) (partial: 10/20)")
    elif result.get("json_exists") and result.get("json_is_new"):
        feedback.append("JSON report missing required schema fields")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }