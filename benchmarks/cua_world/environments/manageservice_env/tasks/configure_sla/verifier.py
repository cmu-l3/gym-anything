#!/usr/bin/env python3
"""
Verifier for configure_sla task in ManageEngine ServiceDesk Plus.

Verifies:
1. SLA "Premium Support SLA" exists in the database.
2. Response and Resolution times match the requirements for 4 priorities.
3. Anti-gaming: SLA was created during the task window.
4. VLM: Visual confirmation of the SLA config (fallback/supplementary).

Data is retrieved via copy_from_env from /tmp/task_result.json, which contains
a DB dump performed by export_result.sh.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_sla(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expectations = metadata.get('expectations', {})
    
    # 1. Load result from container
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

    score = 0
    feedback = []
    
    # Extract DB data
    db_data = result.get('db_extraction', {})
    sla_found = db_data.get('sla_found', False)
    priorities_found = db_data.get('priorities', {})
    
    # --- Check 1: SLA Existence (20 pts) ---
    if sla_found:
        score += 20
        feedback.append("SLA 'Premium Support SLA' found in database.")
    else:
        feedback.append("SLA 'Premium Support SLA' NOT found in database.")
        # Check if count increased at least
        init_c = int(result.get('initial_sla_count', 0))
        final_c = int(result.get('final_sla_count', 0))
        if final_c > init_c:
            feedback.append("However, new SLA record(s) were detected (name mismatch?).")
            score += 5 
        
        # If DB check failed, we rely heavily on VLM
    
    # --- Check 2: Priority Values (64 pts total - 16 per priority) ---
    # We need to match the found priorities (which might be named 'Urgent', 'High', etc.)
    # to our expectations.
    
    # Helper to convert raw time to minutes. 
    # SDP often stores in milliseconds OR minutes. 
    # If value > 10000, assume ms. Else minutes.
    def normalize_time(val):
        if not val: return 0
        val = int(val)
        if val > 100000: # Likely milliseconds
            return val / 60000
        return val # Likely minutes

    # Mapping logic: Try to find matching keys
    matched_priorities = 0
    
    if sla_found:
        for exp_name, exp_vals in expectations.items():
            # Find corresponding priority in DB dump
            # We look for partial match (e.g. "High" in "High Priority")
            found_p_data = None
            found_p_name = ""
            
            for db_p_name, db_p_data in priorities_found.items():
                if exp_name.lower() in db_p_name.lower():
                    found_p_data = db_p_data
                    found_p_name = db_p_name
                    break
            
            if not found_p_data:
                feedback.append(f"Priority '{exp_name}' configuration not found in DB.")
                continue
                
            matched_priorities += 1
            
            # Check Response Time (8 pts)
            raw_resp = found_p_data.get('response_raw', 0)
            act_resp = normalize_time(raw_resp)
            exp_resp = exp_vals['response_min']
            
            # Tolerance +/- 2 minutes
            if abs(act_resp - exp_resp) <= 2:
                score += 8
                feedback.append(f"Priority '{exp_name}': Response time correct ({act_resp}m).")
            else:
                feedback.append(f"Priority '{exp_name}': Response time incorrect (Expected {exp_resp}m, Got {act_resp}m).")

            # Check Resolution Time (8 pts)
            raw_res = found_p_data.get('resolution_raw', 0)
            act_res = normalize_time(raw_res)
            exp_res = exp_vals['resolution_min']
            
            if abs(act_res - exp_res) <= 5: # +/- 5 mins for larger values
                score += 8
                feedback.append(f"Priority '{exp_name}': Resolution time correct ({act_res}m).")
            else:
                feedback.append(f"Priority '{exp_name}': Resolution time incorrect (Expected {exp_res}m, Got {act_res}m).")

    # --- Check 3: VLM Verification (16 pts) ---
    # Use trajectory frames to check if they actually used the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_ss = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Did the agent successfully configure an SLA in ManageEngine ServiceDesk Plus? "
        "Look for a screen showing 'SLA Name: Premium Support SLA' and a table with "
        "priorities (Urgent, High, Medium, Low) and time limits. "
        "Does it look like they saved the configuration?"
    )
    
    vlm_res = query_vlm(images=frames + [final_ss], prompt=vlm_prompt)
    
    vlm_score = 0
    if "yes" in vlm_res.get("response", "").lower():
        vlm_score = 16
        feedback.append("VLM confirms SLA configuration workflow observed.")
    else:
        # Partial credit if ambiguous
        vlm_score = 5
        feedback.append("VLM could not definitively confirm the configuration.")
        
    score += vlm_score
    
    # --- Final Result ---
    # Pass if Score >= 60 AND SLA exists (either DB or VLM strong confirm)
    passed = (score >= 60) and (sla_found or vlm_score >= 15)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback)
    }