#!/usr/bin/env python3
"""
Verifier for correct_reversed_polarity task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_reversed_polarity(traj, env_info, task_info):
    """
    Verify the agent corrected the reversed polarity and set up feeds.
    
    Criteria:
    1. Input process chain exists.
    2. 'Scale' process (-1) exists.
    3. 'Log to feed' (solar_yield) exists.
    4. 'Power to kWh' (solar_energy) exists.
    5. ORDER CHECK: Scale MUST be before Log.
    6. Value Check: solar_yield feed must have positive value (since input is negative).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    chain = result.get('process_chain', [])
    feeds = result.get('feeds', {})
    
    # Analyze Chain
    has_scale = False
    scale_idx = -1
    
    has_log = False
    log_idx = -1
    
    has_kwh = False
    
    for i, step in enumerate(chain):
        # Scale Check (ID 2, Arg -1)
        if step['process_id'] == 2 and str(step['target']) == "-1":
            has_scale = True
            scale_idx = i
            
        # Log Check (ID 1, Target 'solar_yield')
        if step['process_id'] == 1 and step['target'] == "solar_yield":
            has_log = True
            log_idx = i
            
        # kWh Check (ID 4 or 5, Target 'solar_energy')
        if (step['process_id'] == 4 or step['process_id'] == 5) and step['target'] == "solar_energy":
            has_kwh = True

    # Scoring
    if has_scale:
        score += 20
        feedback.append("Scale process (-1) found.")
    else:
        feedback.append("Missing Scale (-1) process.")
        
    if has_log:
        score += 20
        feedback.append("Log to feed 'solar_yield' found.")
    else:
        feedback.append("Missing feed 'solar_yield'.")
        
    if has_kwh:
        score += 20
        feedback.append("Power to kWh 'solar_energy' found.")
    else:
        feedback.append("Missing feed 'solar_energy'.")
        
    # Order Check
    if has_scale and has_log:
        if scale_idx < log_idx:
            score += 20
            feedback.append("Correct Order: Scaled before logging.")
        else:
            feedback.append("INCORRECT ORDER: Logged before scaling (values are still negative).")
    
    # Data Value Check
    # If the setup is correct, the feed value should be positive
    # The simulation sends negative values.
    yield_data = feeds.get('solar_yield', {})
    if yield_data.get('exists', False):
        val = yield_data.get('value', 0)
        if val > 0:
            score += 20
            feedback.append(f"Feed value is positive ({val} W). Polarity corrected.")
        elif val < 0:
            feedback.append(f"Feed value is negative ({val} W). Polarity NOT corrected.")
        else:
            # Value is 0. Could be night or no data.
            # Simulation ensures non-zero, so 0 likely means no data flowing.
            feedback.append("Feed value is 0. Check data flow.")
            
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }