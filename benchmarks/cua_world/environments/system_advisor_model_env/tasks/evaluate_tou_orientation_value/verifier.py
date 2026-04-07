#!/usr/bin/env python3
"""Verifier for evaluate_tou_orientation_value task.

Compares the agent's reported South/West generation and TOU value calculations
against mathematically exact ground-truth values generated during task setup.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tou_orientation_value(traj, env_info, task_info):
    """
    Verify the agent correctly calculated Time-of-Use values for South vs West PV orientations.

    Scoring: 100 points max
    - File Exists & Modified: 10 pts
    - Python executed/PySAM used: 5 pts
    - Schema valid (all fields present): 15 pts
    - South Energy correct (±5% of GT): 15 pts
    - West Energy correct (±5% of GT): 15 pts
    - South TOU Value correct (±5% of GT): 15 pts
    - West TOU Value correct (±5% of GT): 15 pts
    - Orientation Decision correct: 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    passed = False

    # 1. File existence & modification
    file_exists = result.get('file_exists', False)
    file_modified = result.get('file_modified', False)
    
    if file_exists and file_modified:
        score += 10
        feedback_parts.append("File created correctly")
    elif file_exists:
        score += 5
        feedback_parts.append("File exists but modified timestamp invalid")
    else:
        return {"passed": False, "score": 0, "feedback": "Output JSON file not found"}

    # 2. Python Ran
    if result.get('python_ran', False):
        score += 5
        feedback_parts.append("Python script usage detected")
    else:
        feedback_parts.append("No Python/PySAM usage detected")

    # 3. Ground Truth Availability
    gt = result.get('ground_truth', {})
    if not gt.get('gt_success', False):
        logger.warning("Ground truth generation failed in setup. Falling back to generic bounds.")
        # Fallback values for Phoenix 500kW
        gt = {
            "south_annual_energy_kwh": 950000,
            "west_annual_energy_kwh": 815000,
            "south_annual_value_usd": 105000,
            "west_annual_value_usd": 115000,
            "higher_value_orientation": "West"
        }
        tolerance = 0.15 # looser tolerance if exact GT is broken
    else:
        tolerance = 0.05 # strict 5% tolerance

    agent_data = result.get('agent_data', {})
    
    # 4. Schema check
    expected_keys = [
        "south_annual_energy_kwh", 
        "west_annual_energy_kwh", 
        "south_annual_value_usd", 
        "west_annual_value_usd", 
        "higher_value_orientation"
    ]
    
    missing_keys = [k for k in expected_keys if k not in agent_data]
    if not missing_keys:
        score += 15
        feedback_parts.append("Schema is strictly valid")
    else:
        feedback_parts.append(f"Missing keys in JSON: {missing_keys}")
        
    def check_value(key, pts):
        val = agent_data.get(key)
        if val is None:
            return 0
        try:
            val = float(val)
            gt_val = float(gt[key])
            if gt_val == 0:
                return 0
            err = abs(val - gt_val) / gt_val
            if err <= tolerance:
                feedback_parts.append(f"{key} is accurate (±{tolerance*100}%)")
                return pts
            elif err <= tolerance * 2:
                feedback_parts.append(f"{key} is partially accurate (±{tolerance*200}%)")
                return pts / 2
            else:
                feedback_parts.append(f"{key} is inaccurate (Agent: {val:.1f}, GT: {gt_val:.1f})")
                return 0
        except (ValueError, TypeError):
            return 0

    # 5. Math Checks
    score += check_value("south_annual_energy_kwh", 15)
    score += check_value("west_annual_energy_kwh", 15)
    score += check_value("south_annual_value_usd", 15)
    score += check_value("west_annual_value_usd", 15)

    # 6. Orientation Decision Check
    agent_orientation = str(agent_data.get("higher_value_orientation", "")).strip().lower()
    gt_orientation = str(gt.get("higher_value_orientation", "")).strip().lower()
    
    if agent_orientation == gt_orientation:
        score += 10
        feedback_parts.append(f"Correct orientation decision: {gt_orientation.capitalize()}")
    elif agent_orientation:
        feedback_parts.append(f"Incorrect orientation decision: expected {gt_orientation.capitalize()}")

    # Determine Pass/Fail
    # To pass: Need at least 80 points, indicating strong math alignment
    key_criteria_met = file_exists and score >= 80
    passed = key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }