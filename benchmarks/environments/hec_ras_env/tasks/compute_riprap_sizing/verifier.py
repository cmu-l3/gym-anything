#!/usr/bin/env python3
"""
Verifier for compute_riprap_sizing task.

Verification Logic:
1. Simulation Execution: Agent must run HEC-RAS to generate results (checked via timestamps).
2. Data Extraction: Agent's identified max velocity and river station must match ground truth from HDF5.
3. Physics Calculation: Agent's D50 must match the Isbash equation for their inputs.
4. Output Format: CSV must exist and contain correct columns.
"""

import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_riprap_sizing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    # Constants from task description
    CONST_C = 1.20
    CONST_G = 32.174
    CONST_SG = 2.65
    
    # 1. Check Simulation Execution (10 pts)
    if result.get('simulation_run', False):
        score += 10
        feedback.append("HEC-RAS simulation executed successfully.")
    else:
        feedback.append("HEC-RAS simulation results not found or not created during task.")

    # 2. Check CSV Existence and Format (10 pts)
    agent_data = result.get('agent_data', {})
    if result.get('csv_exists', False) and agent_data:
        score += 10
        feedback.append("Output CSV created.")
    else:
        feedback.append("Output CSV missing or empty.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 3. Check Velocity Extraction Accuracy (40 pts)
    ground_truth = result.get('ground_truth', {})
    if not ground_truth.get('ground_truth_available', False):
        # Fallback if ground truth calculation failed inside container
        feedback.append("Warning: Could not verify exact velocity values (ground truth missing). checking internal consistency only.")
        true_vel = None
    else:
        true_vel = ground_truth.get('true_max_velocity')
        true_rs = ground_truth.get('true_river_station')
        
        agent_vel = agent_data.get('max_velocity_fps', 0)
        agent_rs = agent_data.get('river_station', '').strip()
        
        # Check River Station (20 pts)
        if agent_rs == true_rs:
            score += 20
            feedback.append(f"Correctly identified critical River Station: {true_rs}.")
        else:
            feedback.append(f"Incorrect River Station. Expected: {true_rs}, Got: {agent_rs}.")
            
        # Check Velocity Value (20 pts)
        # Allow 5% tolerance
        if true_vel is not None and abs(agent_vel - true_vel) / (true_vel + 1e-6) < 0.05:
            score += 20
            feedback.append(f"Velocity extraction accurate ({agent_vel} fps).")
        else:
            feedback.append(f"Velocity inaccurate. Expected: ~{true_vel}, Got: {agent_vel}.")

    # 4. Check Calculation Consistency (Isbash Formula) (30 pts)
    # Even if velocity is wrong, if the math is consistent, give partial credit for coding the formula correctly.
    try:
        v_used = float(agent_data.get('max_velocity_fps', 0))
        d50_reported = float(agent_data.get('required_d50_ft', 0))
        
        # Calculate expected D50 based on V_used
        # D50 = V^2 / (C^2 * 2g * (Sg-1))
        # Denom = 1.2^2 * 64.348 * 1.65 = 1.44 * 64.348 * 1.65 = 152.89
        denominator = (CONST_C**2) * (2 * CONST_G) * (CONST_SG - 1)
        expected_d50 = (v_used**2) / denominator
        
        if abs(d50_reported - expected_d50) < 0.05 or abs(d50_reported - expected_d50) / (expected_d50 + 1e-6) < 0.05:
            score += 30
            feedback.append("Isbash equation implemented correctly.")
        else:
            feedback.append(f"Isbash calculation incorrect. For V={v_used}, expected D50={expected_d50:.3f}, got {d50_reported}.")
            
    except (ValueError, TypeError):
        feedback.append("Could not parse numerical values from CSV.")

    # 5. Check Unit Conversion (10 pts)
    try:
        d50_ft = float(agent_data.get('required_d50_ft', 0))
        d50_in = float(agent_data.get('required_d50_in', 0))
        if abs(d50_ft * 12 - d50_in) < 0.1:
            score += 10
            feedback.append("Unit conversion (ft to in) correct.")
        else:
            feedback.append("Unit conversion incorrect.")
    except:
        pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }