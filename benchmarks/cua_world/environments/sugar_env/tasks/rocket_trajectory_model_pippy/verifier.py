#!/usr/bin/env python3
"""Verifier for rocket_trajectory_model_pippy task.

Validates that the agent correctly simulated the physics of the water rocket 
and formatted the resulting time-series CSV data strictly to instructions.
"""

import json
import os
import csv
import tempfile
import re


def is_2_decimal_format(val_str):
    """Checks if a numeric string is formatted to exactly 2 decimal places."""
    val_str = val_str.strip()
    return bool(re.match(r'^-?\d+\.\d{2}$', val_str))


def verify_rocket_trajectory_model(traj, env_info, task_info):
    """Verify the python script and output CSV were generated correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read the export JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/rocket_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # Criterion 1: Script exists (10 pts)
    if result.get('script_exists'):
        score += 10
        feedback.append("trajectory_model.py script found")
    else:
        feedback.append("trajectory_model.py script not found")

    # Criterion 2: CSV exists and was modified during task (10 pts)
    csv_exists = result.get('csv_exists', False)
    if csv_exists:
        if result.get('csv_modified'):
            score += 10
            feedback.append("rocket_trajectory.csv found and modified")
        else:
            score += 5
            feedback.append("rocket_trajectory.csv found but pre-existing (mtime failed)")
    else:
        feedback.append("FAIL: rocket_trajectory.csv not found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 2. Read the exported CSV file
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/rocket_trajectory.csv", temp_csv.name)
        with open(temp_csv.name, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    if not rows:
        feedback.append("FAIL: CSV file is empty")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 3: Headers correct (10 pts)
    header = [col.strip() for col in rows[0]]
    if header == ["Time", "X", "Y"]:
        score += 10
        feedback.append("CSV headers correct")
    else:
        feedback.append(f"Incorrect CSV headers: {header} (Expected: ['Time', 'X', 'Y'])")

    data_rows = rows[1:]
    if not data_rows:
        feedback.append("FAIL: No data rows found in CSV")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Parse formatting and maths
    formatting_valid = True
    parsed_data = []
    
    for row in data_rows:
        if len(row) < 3:
            continue
            
        t_str, x_str, y_str = row[0], row[1], row[2]
        
        # Check formatting strictly (2 decimal places)
        if not (is_2_decimal_format(t_str) and is_2_decimal_format(x_str) and is_2_decimal_format(y_str)):
            formatting_valid = False
            
        try:
            parsed_data.append((float(t_str), float(x_str), float(y_str)))
        except ValueError:
            pass

    if not parsed_data:
        feedback.append("FAIL: Could not parse numerical data in CSV")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 4: Data Formatting (15 pts)
    if formatting_valid:
        score += 15
        feedback.append("Data formatting correct (exactly 2 decimal places)")
    else:
        feedback.append("Data formatting incorrect (values not strictly 2 decimal places e.g., '15.00')")

    # Physical checks dictionaries to extract milestones
    initial_state_ok = False
    waypoint_1_ok = False
    waypoint_2_ok = False

    for (t, x, y) in parsed_data:
        # Criterion 5: Initial State Check
        if abs(t - 0.0) < 0.05 and abs(x - 0.0) < 0.1 and abs(y - 0.0) < 0.1:
            initial_state_ok = True
            
        # Criterion 6: Waypoint 1 Check (t=1.0)
        # Expected X: 15.00, Y: 21.08
        if abs(t - 1.0) < 0.05:
            if abs(x - 15.0) < 0.2 and abs(y - 21.08) < 0.2:
                waypoint_1_ok = True
                
        # Criterion 7: Waypoint 2 Check (t=2.0)
        # Expected X: 30.00, Y: 32.36
        if abs(t - 2.0) < 0.05:
            if abs(x - 30.0) < 0.2 and abs(y - 32.36) < 0.2:
                waypoint_2_ok = True

    if initial_state_ok:
        score += 10
        feedback.append("Initial state (t=0) accurate")
    if waypoint_1_ok:
        score += 15
        feedback.append("Waypoint 1 (t=1.0) accurate")
    if waypoint_2_ok:
        score += 15
        feedback.append("Waypoint 2 (t=2.0) accurate")

    # Criterion 8: End Condition Check (15 pts)
    # The trajectory should stop before Y goes negative. Final t should be 5.3s.
    final_t = parsed_data[-1][0]
    final_y = parsed_data[-1][2]
    has_negative_y = any(y < 0 for (_, _, y) in parsed_data)
    
    if abs(final_t - 5.3) < 0.05 and not has_negative_y:
        score += 15
        feedback.append("End condition correct (Terminated at t=5.3, no negative Y)")
    elif not has_negative_y:
        feedback.append(f"End condition partial (No negative Y, but ended at t={final_t} instead of 5.3)")
    else:
        feedback.append("End condition failed (CSV contains negative Y values)")

    # Pass logic: Must have standard structure and correctly hit physics milestones
    passed = score >= 70 and csv_exists and initial_state_ok and waypoint_1_ok
    
    if passed:
        feedback.append("SUCCESS: Physics trajectory perfectly modelled.")
    else:
        feedback.append(f"FAILED: Score {score} < 70 or critical checks missed.")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "csv_valid": csv_exists,
            "formatting_valid": formatting_valid,
            "physics_accurate": waypoint_1_ok and waypoint_2_ok
        }
    }