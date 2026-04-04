#!/usr/bin/env python3
"""
Verifier for add_procedure_provider task in LibreHealth EHR.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_procedure_provider(traj, env_info, task_info):
    """
    Verifies that the procedure provider was added correctly to the database.
    """
    # 1. Retrieve result data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    record_found = result.get('record_found', False)
    data = result.get('record_data', {})
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    # Metadata expectations
    meta = task_info.get('metadata', {})
    exp_npi = meta.get('expected_npi', '1234567893')
    exp_send_app = meta.get('expected_send_app', 'LIBREEHR')
    exp_send_fac = meta.get('expected_send_fac', 'CLINIC01')
    exp_recv_app = meta.get('expected_recv_app', 'LABCORP')
    exp_recv_fac = meta.get('expected_recv_fac', 'LC7890')
    exp_host = meta.get('expected_host', 'sftp.labcorp-example.com')

    score = 0
    feedback_lines = []

    # 3. Scoring Logic
    
    # CRITERION 1: Record Exists (Gatekeeper) - 20 pts
    if record_found:
        score += 20
        feedback_lines.append("Success: LabCorp provider record found in database.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Fail: No LabCorp provider record found in database."
        }

    # CRITERION 2: Field Validation
    
    # NPI (15 pts)
    actual_npi = data.get('npi', '')
    if actual_npi == exp_npi:
        score += 15
        feedback_lines.append(f"Correct NPI: {actual_npi}")
    else:
        feedback_lines.append(f"Incorrect NPI: expected {exp_npi}, got '{actual_npi}'")

    # IDs (20 pts total, 5 each)
    # Send App
    if exp_send_app.lower() in data.get('send_app_id', '').lower():
        score += 5
    else:
        feedback_lines.append(f"Incorrect Send App ID: got '{data.get('send_app_id')}'")
        
    # Send Fac
    if exp_send_fac.lower() in data.get('send_fac_id', '').lower():
        score += 5
    else:
        feedback_lines.append(f"Incorrect Send Facility ID: got '{data.get('send_fac_id')}'")

    # Recv App
    if exp_recv_app.lower() in data.get('recv_app_id', '').lower():
        score += 5
    else:
        feedback_lines.append(f"Incorrect Recv App ID: got '{data.get('recv_app_id')}'")
        
    # Recv Fac
    if exp_recv_fac.lower() in data.get('recv_fac_id', '').lower():
        score += 5
    else:
        feedback_lines.append(f"Incorrect Recv Facility ID: got '{data.get('recv_fac_id')}'")

    # Host (10 pts)
    if exp_host.lower() in data.get('remote_host', '').lower():
        score += 10
        feedback_lines.append("Correct Remote Host")
    else:
        feedback_lines.append(f"Incorrect Remote Host: got '{data.get('remote_host')}'")
        
    # Protocol (10 pts)
    # We accept 'DL' or similar indications of download protocol if the system maps names to codes
    protocol = data.get('protocol', '')
    if protocol and protocol != 'NULL':
        score += 10
        feedback_lines.append(f"Protocol set to: {protocol}")
    else:
        feedback_lines.append("Protocol not set")

    # CRITERION 3: Anti-gaming / State Change (10 pts)
    if current_count > initial_count:
        score += 10
        feedback_lines.append("Provider count increased successfully.")
    else:
        feedback_lines.append("Warning: Total provider count did not increase (modified existing?)")

    # CRITERION 4: VLM Workflow Check (10 pts)
    # We check if the agent actually used the UI (Screenshots exist and are valid)
    # Since we don't have the VLM model loaded here in this script, we rely on the framework
    # to pass trajectory. For this verifier, we check if screenshot exists and implies activity.
    # In a full production env, we would call `query_vlm`.
    # Here, we award points if the record exists + screenshots present, implying UI usage.
    if traj and len(traj) > 0:
        score += 10
        feedback_lines.append("Trajectory evidence present.")
    
    passed = score >= 60 and record_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_lines)
    }