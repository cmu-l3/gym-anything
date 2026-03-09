#!/usr/bin/env python3
"""
Verifier for compute_channel_morphology task.
Compares agent's JSON output against ground truth calculated from HDF5 file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_channel_morphology(traj, env_info, task_info):
    """
    Verify the computed channel morphology metrics.
    
    Criteria:
    1. Output JSON exists and parses correctly (20 pts)
    2. Computed values match Ground Truth within 5% tolerance:
       - Channel Length (20 pts)
       - Sinuosity (15 pts)
       - Average Bed Slope (15 pts)
    3. Invert elevations match exactly/closely (20 pts)
    4. Valid JSON structure (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Checks
    output_exists = result.get('output_exists', False)
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Output file morphology_metrics.json not found"}

    agent_data = result.get('agent_output', {})
    ground_truth = result.get('ground_truth', {})
    
    # Check for Ground Truth errors (if script failed in container)
    if 'error' in ground_truth:
        return {"passed": False, "score": 0, "feedback": f"Verification failed due to internal error: {ground_truth['error']}"}

    score = 0
    feedback = []

    # 1. Structure Check (20 + 10 pts)
    required_keys = ['channel_length_ft', 'sinuosity_index', 'average_bed_slope', 'upstream_invert_el_ft']
    missing_keys = [k for k in required_keys if k not in agent_data]
    
    if not missing_keys:
        score += 30
        feedback.append("JSON structure valid")
    else:
        feedback.append(f"Missing keys: {missing_keys}")
        score += 10 # Partial for file existence

    # Helper for comparison
    def check_val(key, points, tolerance_pct=5.0):
        if key not in agent_data or key not in ground_truth:
            return 0, f"Missing {key}"
        
        agent_val = float(agent_data[key])
        truth_val = float(ground_truth[key])
        
        if truth_val == 0:
            diff = abs(agent_val - truth_val)
            is_close = diff < 0.001
        else:
            pct_diff = abs((agent_val - truth_val) / truth_val) * 100
            is_close = pct_diff <= tolerance_pct
            
        if is_close:
            return points, f"{key} correct ({agent_val:.4f})"
        else:
            return 0, f"{key} incorrect (Agent: {agent_val:.4f}, Truth: {truth_val:.4f})"

    # 2. Value Checks
    # Channel Length (20 pts)
    s, f = check_val('channel_length_ft', 20)
    score += s
    feedback.append(f)

    # Sinuosity (15 pts)
    s, f = check_val('sinuosity_index', 15)
    score += s
    feedback.append(f)

    # Slope (15 pts)
    s, f = check_val('average_bed_slope', 15)
    score += s
    feedback.append(f)

    # Inverts (20 pts total)
    s1, f1 = check_val('upstream_invert_el_ft', 10, tolerance_pct=1.0)
    s2, f2 = check_val('downstream_invert_el_ft', 10, tolerance_pct=1.0)
    score += s1 + s2
    feedback.append(f1)
    feedback.append(f2)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }