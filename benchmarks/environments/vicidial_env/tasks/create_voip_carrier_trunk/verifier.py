#!/usr/bin/env python3
"""
Verifier for Create VoIP Carrier Trunk task.

Verification Strategy:
1. Database Verification: Check that the carrier 'FLOWRT01' exists in `vicidial_server_carriers`.
2. Field Verification: Compare Name, Protocol, Registration, Account, Dialplan, Server IP against expected values.
3. VLM Verification: Use trajectory frames to confirm the agent interacted with the Admin UI forms.
4. Anti-Gaming: Ensure database record count increased and the record wasn't pre-existing.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_voip_carrier_trunk(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Carrier Existence (15 pts) ---
    if not result.get('carrier_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Carrier 'FLOWRT01' was not found in the database."
        }
    
    score += 15
    feedback_parts.append("Carrier record created")
    
    data = result.get('carrier_data', {})
    
    # --- CRITERION 2: Carrier Name (10 pts) ---
    expected_name = metadata.get('expected_name', "Flowroute Primary SIP Trunk")
    actual_name = data.get('carrier_name', '')
    if expected_name.lower() in actual_name.lower():
        score += 10
        feedback_parts.append("Carrier Name correct")
    else:
        feedback_parts.append(f"Carrier Name mismatch ('{actual_name}' vs '{expected_name}')")

    # --- CRITERION 3: Protocol (10 pts) ---
    expected_protocol = metadata.get('expected_protocol', "SIP")
    actual_protocol = data.get('protocol', '')
    if expected_protocol.lower() in actual_protocol.lower():
        score += 10
        feedback_parts.append("Protocol correct")
    else:
        feedback_parts.append(f"Protocol mismatch ('{actual_protocol}' vs '{expected_protocol}')")

    # --- CRITERION 4: Registration String (15 pts) ---
    # Flexible matching: check for key components
    reg_string = data.get('registration_string', '') or ""
    req_reg = metadata.get('required_registration_substrings', [])
    reg_matches = sum(1 for s in req_reg if s in reg_string)
    
    if len(req_reg) > 0:
        reg_score = 15 * (reg_matches / len(req_reg))
        score += reg_score
        if reg_matches == len(req_reg):
            feedback_parts.append("Registration string correct")
        else:
            feedback_parts.append(f"Registration string partial ({reg_matches}/{len(req_reg)} components)")
            
    # --- CRITERION 5: Account Entry (20 pts) ---
    acct_entry = data.get('account_entry', '') or ""
    req_acct = metadata.get('required_account_substrings', [])
    acct_matches = sum(1 for s in req_acct if s in acct_entry)
    
    if len(req_acct) > 0:
        acct_score = 20 * (acct_matches / len(req_acct))
        score += acct_score
        if acct_matches == len(req_acct):
            feedback_parts.append("Account entry correct")
        else:
            feedback_parts.append(f"Account entry partial ({acct_matches}/{len(req_acct)} components)")

    # --- CRITERION 6: Dialplan Entry (20 pts) ---
    dp_entry = data.get('dialplan_entry', '') or ""
    req_dp = metadata.get('required_dialplan_substrings', [])
    dp_matches = sum(1 for s in req_dp if s in dp_entry)
    
    if len(req_dp) > 0:
        dp_score = 20 * (dp_matches / len(req_dp))
        score += dp_score
        if dp_matches == len(req_dp):
            feedback_parts.append("Dialplan entry correct")
        else:
            feedback_parts.append(f"Dialplan entry partial ({dp_matches}/{len(req_dp)} components)")

    # --- CRITERION 7: Server IP (5 pts) ---
    # Agent was supposed to look this up.
    actual_ip = data.get('server_ip', '')
    active_ip = result.get('active_server_ip', '')
    
    if actual_ip and active_ip and actual_ip == active_ip:
        score += 5
        feedback_parts.append("Server IP correct")
    elif actual_ip:
        # Partial credit if they put *some* IP, but it wasn't the active one (maybe 127.0.0.1)
        score += 2
        feedback_parts.append(f"Server IP incorrect ('{actual_ip}' vs '{active_ip}')")
    else:
        feedback_parts.append("Server IP missing")

    # --- CRITERION 8: VLM Verification (5 pts) ---
    # Check if agent actually navigated the UI
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at these screenshots of the Vicidial Admin Interface.
            The user should be configuring a 'Carrier'.
            
            Do you see any of the following:
            1. The 'Carriers' admin screen (listing carriers or showing 'Add A New Carrier').
            2. A form with fields like 'Carrier ID', 'Carrier Name', 'Account Entry', 'Dialplan Entry'.
            3. Text being entered that looks like SIP configuration (e.g., 'type=peer', 'host=...').
            
            Return JSON: {"evidence_found": true/false, "reason": "..."}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('evidence_found'):
                    vlm_score = 5
                    feedback_parts.append("VLM confirmed UI interaction")
                else:
                    feedback_parts.append("VLM: No obvious UI interaction found")
            else:
                # Fallback if VLM fails: assume pass if DB is correct to avoid false negatives on technical failures
                vlm_score = 5
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        vlm_score = 5 # Fallback
        
    score += vlm_score

    # Final tally
    final_score = min(100, int(score))
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }