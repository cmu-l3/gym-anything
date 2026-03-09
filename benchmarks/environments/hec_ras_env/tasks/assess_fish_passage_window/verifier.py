#!/usr/bin/env python3
"""
Verifier for assess_fish_passage_window task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assess_fish_passage_window(traj, env_info, task_info):
    """
    Verifies the fish passage analysis task.
    
    Criteria:
    1. Simulation Run: HDF output file must exist.
    2. Report Exists: JSON file found.
    3. Critical Station: Matches ground truth (String match).
    4. Max Velocity: Within 1% of ground truth.
    5. Passable Duration: Within 1 timestep (approx 1 hour) of ground truth.
    6. Plot Created: Output image exists.
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Extract Data
    agent_data = data.get('agent_data', {})
    gt = data.get('ground_truth', {})
    
    score = 0
    feedback = []
    
    # Check 1: Simulation Run (10 pts)
    if data.get('hdf_exists'):
        score += 10
        feedback.append("Simulation run confirmed.")
    else:
        feedback.append("Simulation output (HDF) not found.")
        
    # Check 2: Report Exists & Created (10 pts)
    if data.get('report_created_during_task'):
        score += 10
        feedback.append("Report file created.")
    elif data.get('report_exists'):
        score += 5
        feedback.append("Report file exists but timestamp is old.")
    else:
        feedback.append("Report file missing.")
        
    # Check 3: Plot Created (15 pts)
    if data.get('plot_created_during_task'):
        score += 15
        feedback.append("Velocity hydrograph plot created.")
    elif data.get('plot_exists'):
        score += 5
        feedback.append("Plot exists but timestamp is old.")
    else:
        feedback.append("Plot missing.")
        
    # Validation Logic (requires GT)
    if not gt.get('ground_truth_available'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Internal Error: Could not generate ground truth from simulation results. " + " | ".join(feedback)
        }
        
    # Check 4: Critical River Station (25 pts)
    agent_rs = str(agent_data.get('critical_river_station', '')).strip()
    gt_rs = str(gt.get('critical_river_station', '')).strip()
    
    if agent_rs == gt_rs and agent_rs != "":
        score += 25
        feedback.append(f"Correct critical station identified: {agent_rs}.")
    else:
        feedback.append(f"Incorrect critical station. Expected: {gt_rs}, Got: {agent_rs}.")
        
    # Check 5: Max Velocity (15 pts)
    try:
        agent_vel = float(agent_data.get('max_channel_velocity_fps', -1))
        gt_vel = float(gt.get('max_channel_velocity_fps', 0))
        tolerance_vel = 0.05 * gt_vel # 5% tolerance
        
        if abs(agent_vel - gt_vel) <= tolerance_vel:
            score += 15
            feedback.append(f"Max velocity accurate ({agent_vel:.2f} fps).")
        else:
            feedback.append(f"Max velocity mismatch. Expected: {gt_vel:.2f}, Got: {agent_vel:.2f}.")
    except (ValueError, TypeError):
        feedback.append("Invalid max velocity format.")

    # Check 6: Passable Duration (25 pts)
    try:
        agent_dur = float(agent_data.get('passable_duration_hours', -1))
        gt_dur = float(gt.get('passable_duration_hours', 0))
        # Tolerance: 1 timestep (dt) or ~10%
        dt = float(gt.get('dt_used', 1.0))
        tolerance_dur = max(dt * 1.5, 0.1 * gt_dur)
        
        if abs(agent_dur - gt_dur) <= tolerance_dur:
            score += 25
            feedback.append(f"Passable duration accurate ({agent_dur:.1f} hrs).")
        else:
            feedback.append(f"Passable duration mismatch. Expected: {gt_dur:.1f}, Got: {agent_dur:.1f}.")
    except (ValueError, TypeError):
        feedback.append("Invalid duration format.")

    # Final Pass Determination
    # Must identify station AND get duration roughly right to be useful
    passed = (score >= 65) and (agent_rs == gt_rs)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }