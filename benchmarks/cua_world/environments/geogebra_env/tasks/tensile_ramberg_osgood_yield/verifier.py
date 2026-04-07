#!/usr/bin/env python3
"""
Verifier for Tensile Test Ramberg-Osgood Yield Strength task.

Scoring (100 pts total):
1. File Created During Task (10 pts)
2. Data Points Imported (15 pts): >= 8 point elements found
3. Sliders Present (10 pts): >= 2 slider elements
4. Parameter E Calibration (10 pts): E ~ 69000 within tolerance
5. Parameter K Calibration (10 pts): K ~ 450 within tolerance
6. Parameter n Calibration (10 pts): n ~ 10 within tolerance
7. Model Function Present (10 pts): Function with power expression (^ and /)
8. Yield Point Identified (15 pts): Point near x ~ 242 MPa
9. Text Annotations (10 pts): >= 2 text elements (SSR + yield label)

Pass Threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_tensile_ramberg_osgood_yield(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    true_E = metadata.get('true_E', 69000)
    true_K = metadata.get('true_K', 450)
    true_n = metadata.get('true_n', 10)
    E_tol = metadata.get('E_tolerance', 8000)
    K_tol = metadata.get('K_tolerance', 100)
    n_tol = metadata.get('n_tolerance', 4)
    yield_approx = metadata.get('yield_stress_approx', 242)
    yield_tol = metadata.get('yield_tolerance', 40)
    min_points = metadata.get('min_data_points', 8)

    # 1. Retrieve result JSON from environment
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}

    score = 0
    feedback = []

    # --- Criterion 1: File Created (10 pts) ---
    if result.get('file_found') and result.get('file_created_during_task'):
        score += 10
        feedback.append("File created during task (+10).")
    elif result.get('file_found'):
        score += 3
        feedback.append("File exists but may not have been created during task (+3/10).")
    else:
        feedback.append("File 'tensile_analysis.ggb' not found (0/10).")
        # Early exit — nothing else to check
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # --- Criterion 2: Data Points Imported (15 pts) ---
    num_points = result.get('num_points', 0)
    if num_points >= min_points:
        score += 15
        feedback.append(f"Data imported: {num_points} points found (+15).")
    elif num_points >= 4:
        score += 7
        feedback.append(f"Partial data: {num_points} points (need {min_points}) (+7/15).")
    else:
        feedback.append(f"Insufficient data points: {num_points} found (0/15).")

    # --- Criterion 3: Sliders Present (10 pts) ---
    num_sliders = result.get('num_sliders', 0)
    if num_sliders >= 3:
        score += 10
        feedback.append(f"All 3 sliders found (+10).")
    elif num_sliders >= 2:
        score += 7
        feedback.append(f"{num_sliders} sliders found (+7/10).")
    elif num_sliders >= 1:
        score += 3
        feedback.append(f"Only {num_sliders} slider found (+3/10).")
    else:
        feedback.append("No sliders detected (0/10).")

    # --- Criterion 4: E Calibration (10 pts) ---
    cand_E = result.get('candidate_E')
    if cand_E is not None:
        if abs(cand_E - true_E) <= E_tol:
            score += 10
            feedback.append(f"E calibrated: {cand_E:.0f} (target {true_E} +/- {E_tol}) (+10).")
        else:
            score += 3
            feedback.append(f"E value {cand_E:.0f} outside tolerance ({true_E} +/- {E_tol}) (+3/10).")
    else:
        feedback.append("E parameter not identified (0/10).")

    # --- Criterion 5: K Calibration (10 pts) ---
    cand_K = result.get('candidate_K')
    if cand_K is not None:
        if abs(cand_K - true_K) <= K_tol:
            score += 10
            feedback.append(f"K calibrated: {cand_K:.0f} (target {true_K} +/- {K_tol}) (+10).")
        else:
            score += 3
            feedback.append(f"K value {cand_K:.0f} outside tolerance ({true_K} +/- {K_tol}) (+3/10).")
    else:
        feedback.append("K parameter not identified (0/10).")

    # --- Criterion 6: n Calibration (10 pts) ---
    cand_n = result.get('candidate_n')
    if cand_n is not None:
        if abs(cand_n - true_n) <= n_tol:
            score += 10
            feedback.append(f"n calibrated: {cand_n:.1f} (target {true_n} +/- {n_tol}) (+10).")
        else:
            score += 3
            feedback.append(f"n value {cand_n:.1f} outside tolerance ({true_n} +/- {n_tol}) (+3/10).")
    else:
        feedback.append("n parameter not identified (0/10).")

    # --- Criterion 7: Model Function Present (10 pts) ---
    if result.get('has_power_expression'):
        score += 10
        feedback.append("Ramberg-Osgood function with power expression found (+10).")
    elif result.get('has_function'):
        score += 5
        feedback.append("Function found but no power expression detected (+5/10).")
    else:
        feedback.append("No model function detected (0/10).")

    # --- Criterion 8: Yield Point Identified (15 pts) ---
    yield_x = result.get('yield_point_x')
    if yield_x is not None:
        if abs(yield_x - yield_approx) <= yield_tol:
            score += 15
            feedback.append(f"Yield point found at {yield_x:.1f} MPa (target ~{yield_approx}) (+15).")
        else:
            score += 5
            feedback.append(f"Candidate yield point at {yield_x:.1f} MPa, outside tolerance (+5/15).")
    else:
        # Check if Intersect command was used (partial credit)
        if "Intersect" in result.get('command_list', []):
            score += 5
            feedback.append("Intersect command used but yield point not in expected range (+5/15).")
        else:
            feedback.append("Yield point not identified (0/15).")

    # --- Criterion 9: Text Annotations (10 pts) ---
    num_text = result.get('num_text_elements', 0)
    if num_text >= 2:
        score += 10
        feedback.append(f"{num_text} text annotations found (+10).")
    elif num_text >= 1:
        score += 5
        feedback.append(f"Only {num_text} text annotation found (+5/10).")
    else:
        feedback.append("No text annotations found (0/10).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback),
        "subscores": {
            "file_created": 10 if (result.get('file_found') and result.get('file_created_during_task')) else 0,
            "data_imported": min(15, 15 if num_points >= min_points else (7 if num_points >= 4 else 0)),
            "sliders": min(10, 10 if num_sliders >= 3 else (7 if num_sliders >= 2 else 0)),
            "E_calibration": 10 if (cand_E and abs(cand_E - true_E) <= E_tol) else 0,
            "K_calibration": 10 if (cand_K and abs(cand_K - true_K) <= K_tol) else 0,
            "n_calibration": 10 if (cand_n and abs(cand_n - true_n) <= n_tol) else 0,
            "model_function": 10 if result.get('has_power_expression') else 0,
            "yield_point": 15 if (yield_x and abs(yield_x - yield_approx) <= yield_tol) else 0,
            "text_annotations": min(10, 10 if num_text >= 2 else (5 if num_text >= 1 else 0))
        }
    }
