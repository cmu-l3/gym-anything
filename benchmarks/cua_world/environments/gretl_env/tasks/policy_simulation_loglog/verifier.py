#!/usr/bin/env python3
import json
import logging
import math
import os
import tempfile
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Ground Truth Data (food.gdt content from install_gretl.sh)
# Format: (food_exp, income)
DATA = [
    (115.22, 3.69), (135.98, 4.39), (119.34, 4.75), (114.96, 6.03),
    (187.05, 12.47), (243.43, 12.98), (109.71, 3.15), (197.23, 12.00),
    (263.29, 16.31), (251.84, 12.13), (147.22, 7.99), (230.77, 12.63),
    (182.43, 8.93), (248.13, 10.01), (220.84, 8.79), (337.62, 19.06),
    (167.38, 9.09), (217.37, 10.91), (327.28, 15.18), (355.76, 20.01),
    (176.17, 9.69), (352.86, 20.00), (192.43, 7.63), (207.39, 12.80),
    (321.62, 15.29), (274.54, 15.72), (312.05, 22.66), (261.74, 13.59),
    (263.99, 11.51), (296.24, 17.70), (265.30, 13.85), (313.18, 14.12),
    (300.68, 21.23), (279.22, 16.54), (374.22, 24.22), (377.52, 24.16),
    (260.35, 17.32), (382.14, 25.51), (374.76, 25.08), (404.90, 26.75)
]

def calculate_ground_truth():
    """Calculates the expected aggregate increase."""
    food_exp = np.array([x[0] for x in DATA])
    income = np.array([x[1] for x in DATA])
    
    # Log transformation
    l_food = np.log(food_exp)
    l_income = np.log(income)
    
    # OLS: l_food = b0 + b1 * l_income
    A = np.vstack([np.ones(len(l_income)), l_income]).T
    beta, _, _, _ = np.linalg.lstsq(A, l_food, rcond=None)
    b0, b1 = beta
    
    # Baseline Prediction (levels): exp(b0 + b1 * l_income)
    pred_base = np.exp(b0 + b1 * l_income)
    
    # Counterfactual Prediction (levels): exp(b0 + b1 * log(income * 1.15))
    # log(income * 1.15) = log(income) + log(1.15)
    l_income_new = l_income + np.log(1.15)
    pred_new = np.exp(b0 + b1 * l_income_new)
    
    # Aggregate Difference
    diff = pred_new - pred_base
    total_increase = np.sum(diff)
    
    return total_increase, b0, b1

def verify_policy_simulation(traj, env_info, task_info):
    """
    Verifies the double-log policy simulation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    tolerance = metadata.get('ground_truth_tolerance', 10.0)
    
    # Calculate ground truth
    try:
        expected_increase, b0, b1 = calculate_ground_truth()
        logger.info(f"Ground Truth: Increase={expected_increase:.2f}, b0={b0:.4f}, b1={b1:.4f}")
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier error calculating ground truth: {e}"}

    # Retrieve results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Could not read task results"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Script Exists (20 pts)
    if result.get('script_exists'):
        score += 20
        feedback.append("Script file created.")
    else:
        feedback.append("Script file missing.")

    # Criterion 2: Script Content (20 pts)
    if result.get('script_valid_content'):
        score += 20
        feedback.append("Script contains expected OLS/exp commands.")
    else:
        feedback.append("Script content missing key commands (ols, exp).")

    # Criterion 3: Result File Exists (10 pts)
    if result.get('result_exists'):
        score += 10
        feedback.append("Result file created.")
    else:
        feedback.append("Result file missing.")

    # Criterion 4: Result Accuracy (50 pts)
    agent_value_str = result.get('result_value_str', '').strip()
    try:
        agent_value = float(agent_value_str)
        error = abs(agent_value - expected_increase)
        
        if error <= tolerance:
            score += 50
            feedback.append(f"Result accurate ({agent_value:.2f}).")
        elif error <= tolerance * 2:
            score += 25
            feedback.append(f"Result close but outside tolerance ({agent_value:.2f} vs {expected_increase:.2f}).")
        else:
            feedback.append(f"Result incorrect ({agent_value:.2f} vs {expected_increase:.2f}).")
    except ValueError:
        feedback.append("Result file does not contain a valid number.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "expected": expected_increase,
            "agent_value": agent_value_str,
            "b0": b0,
            "b1": b1
        }
    }