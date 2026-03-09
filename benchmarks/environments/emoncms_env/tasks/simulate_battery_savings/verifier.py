#!/usr/bin/env python3
import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_battery_simulation(traj, env_info, task_info):
    """
    Verify the battery simulation task.
    
    Criteria:
    1. Output file exists and parses as JSON.
    2. Calculated value is within 2% of ground truth (calculated from actual DB data).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy functionality missing"}

    # Retrieve result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Check for internal errors
    if result.get('error_msg'):
        return {"passed": False, "score": 0, "feedback": f"Verification system error: {result['error_msg']}"}

    # Evaluate
    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get('file_exists'):
        score += 10
        feedback.append("Output file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/battery_simulation.json not found."}
    
    # 2. Accuracy Check (90 pts)
    agent_val = result.get('agent_value', 0.0)
    truth_val = result.get('ground_truth_value', 0.0)
    
    if truth_val == 0:
        # Should not happen unless data generation failed
        return {"passed": False, "score": 0, "feedback": "Verification error: Ground truth is 0 (data missing?)."}
        
    delta = abs(agent_val - truth_val)
    percent_error = (delta / truth_val) * 100.0
    
    feedback.append(f"Agent Value: {agent_val:.2f} kWh")
    feedback.append(f"Ground Truth: {truth_val:.2f} kWh")
    feedback.append(f"Error: {percent_error:.2f}%")
    
    if percent_error <= 2.0:
        score += 90
        feedback.append("Calculation is accurate within 2%.")
    elif percent_error <= 5.0:
        score += 50
        feedback.append("Calculation is within 5% (partial credit). Check your integration logic.")
    elif percent_error <= 10.0:
        score += 20
        feedback.append("Calculation is within 10%. Significant deviation found.")
    else:
        feedback.append("Calculation incorrect. Check logic: Charge on Surplus, Discharge on Deficit, Capacity Limit 5kWh.")
        
    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }