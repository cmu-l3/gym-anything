#!/usr/bin/env python3
"""Verifier for dynamic_routing_db_lookup task."""

import json
import tempfile
import os

def verify_dynamic_routing_db_lookup(traj, env_info, task_info):
    """Verify the Dynamic TCP Routing channel configuration and function."""
    
    # 1. Boilerplate: Get results from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/dynamic_routing_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    channel_exists = result.get('channel_exists', False)
    channel_started = result.get('channel_started', False)
    dynamic_config = result.get('dynamic_config_detected', False)
    db_code = result.get('db_code_detected', False)
    routed_a = result.get('routed_clinic_a', False)
    routed_b = result.get('routed_clinic_b', False)

    # 3. Scoring Logic
    score = 0
    feedback_parts = []
    
    # Criterion 1: Channel Exists (10 pts)
    if channel_exists:
        score += 10
        feedback_parts.append("Channel 'Dynamic_Clinic_Router' created.")
    else:
        feedback_parts.append("Channel 'Dynamic_Clinic_Router' NOT found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback_parts)}

    # Criterion 2: Configuration Analysis (20 pts)
    # We check if they used variables ${...} and database code
    if dynamic_config:
        score += 10
        feedback_parts.append("Dynamic variable substitution detected in destination config.")
    else:
        feedback_parts.append("Warning: Dynamic variable substitution (e.g., ${host}) not detected.")
        
    if db_code:
        score += 10
        feedback_parts.append("Database connection code detected in channel.")
    else:
        feedback_parts.append("Warning: Database lookup code not detected.")

    # Criterion 3: Channel Started (10 pts)
    if channel_started:
        score += 10
        feedback_parts.append("Channel is deployed and running.")
    else:
        feedback_parts.append("Channel is NOT running (must be STARTED).")

    # Criterion 4: Functional Routing (60 pts)
    # Critical: Messages must arrive at the correct ports
    if routed_a:
        score += 30
        feedback_parts.append("Success: CLINIC_A message routed correctly to port 6671.")
    else:
        feedback_parts.append("Fail: CLINIC_A message did not reach port 6671.")

    if routed_b:
        score += 30
        feedback_parts.append("Success: CLINIC_B message routed correctly to port 6672.")
    else:
        feedback_parts.append("Fail: CLINIC_B message did not reach port 6672.")

    # 4. Final Determination
    # Pass threshold: 70 points. This requires at least one successful route AND correct configuration setup.
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }