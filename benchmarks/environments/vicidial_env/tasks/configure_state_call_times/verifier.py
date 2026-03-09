#!/usr/bin/env python3
"""
Verifier for configure_state_call_times task.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_state_call_times(traj, env_info, task_info):
    """
    Verify that the agent correctly configured the Call Times and State Call Time mappings.
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

    metadata = task_info.get('metadata', {})
    score = 0
    feedback = []
    
    # 1. Verify Call Times (FL_SAFE, NV_SAFE)
    call_times = result.get("call_times", {})
    
    # FL_SAFE
    fl_safe = call_times.get("FL_SAFE")
    if fl_safe:
        if str(fl_safe.get("start")) == str(metadata.get("fl_start", "1000")) and \
           str(fl_safe.get("stop")) == str(metadata.get("fl_stop", "1800")):
            score += 20
            feedback.append("FL_SAFE configured correctly.")
        else:
            score += 10 # Partial credit for existence
            feedback.append(f"FL_SAFE exists but times wrong (got {fl_safe.get('start')}-{fl_safe.get('stop')}).")
    else:
        feedback.append("FL_SAFE call time not found.")

    # NV_SAFE
    nv_safe = call_times.get("NV_SAFE")
    if nv_safe:
        if str(nv_safe.get("start")) == str(metadata.get("nv_start", "0900")) and \
           str(nv_safe.get("stop")) == str(metadata.get("nv_stop", "2000")):
            score += 20
            feedback.append("NV_SAFE configured correctly.")
        else:
            score += 10
            feedback.append(f"NV_SAFE exists but times wrong (got {nv_safe.get('start')}-{nv_safe.get('stop')}).")
    else:
        feedback.append("NV_SAFE call time not found.")

    # 2. Verify State Call Time Group & Mappings
    sct_rows = result.get("state_call_times", [])
    
    if not sct_rows:
        feedback.append("State Call Time group 'US_STRICT_26' not found.")
    else:
        score += 15 # Group exists
        feedback.append("State Call Time group 'US_STRICT_26' found.")
        
        # Check mappings
        # We need to look for rows that link state to call_time_id
        # Vicidial schema varies, but typically columns are state_call_time_state and state_call_time_id (which is the rule ID, but here group ID) 
        # Wait, usually the 'call_time_id' column in this table specifies the rule.
        
        mappings_found = {"FL": False, "NV": False, "CA": False}
        mappings_correct = {"FL": False, "NV": False, "CA": False}
        
        expected_mappings = metadata.get("mappings", {})
        
        for row in sct_rows:
            # Try to identify columns safely
            # Possible keys: 'state_call_time_state', 'state', etc.
            # And 'call_time_id'
            
            state = row.get("state_call_time_state") or row.get("state")
            ct_id = row.get("call_time_id") or row.get("model_call_time_id") # approximate guess if schema varies
            
            # If we used raw fallback in export (no headers found)
            if "raw" in row:
                # Best guess: ID, state, call_time_id... standard Vicidial is:
                # state_call_time_id, state_call_time_state, call_time_id, ...
                raw = row["raw"]
                if len(raw) >= 3:
                    # Check if index 0 is US_STRICT_26 (group ID)
                    if raw[0] == "US_STRICT_26":
                        state = raw[1]
                        ct_id = raw[2]

            if state in mappings_found:
                mappings_found[state] = True
                if ct_id == expected_mappings[state]:
                    mappings_correct[state] = True

        # Score mappings
        for state in ["FL", "NV", "CA"]:
            if mappings_correct[state]:
                score += 15
                feedback.append(f"Mapping for {state} correct.")
            elif mappings_found[state]:
                score += 5
                feedback.append(f"Mapping for {state} exists but points to wrong ID.")
            else:
                feedback.append(f"Mapping for {state} missing.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }