#!/usr/bin/env python3
"""
Verifier for hospital_medical_gas_inventory task.

Evaluates the exported .t2s JSON parsing using copy_from_env.
Combines programmatic validation of chemical entities with VLM trajectory 
checks to prevent file-dropping spoofing.
"""

import os
import json
import tempfile
import logging

# VLM utilities provided by framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    from gym_anything.vlm import query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hospital_medical_gas_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', "C:\\Users\\Docker\\Desktop\\task_result.json")
    pass_threshold = metadata.get('pass_threshold', 70)

    score = 0
    feedback_parts = []

    # 1. Fetch export data
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Anti-gaming file checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found."}
    if not result.get('modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file is stale (existed before task started)."}
    
    score += 10
    feedback_parts.append("Valid output file created (+10)")

    chemicals = result.get('chemicals', [])
    cas_map = {str(c.get('cas', '')).strip(): c for c in chemicals}

    # 3. Verify Chemical 1: Oxygen (7782-44-7)
    oxy = cas_map.get("7782-44-7")
    if oxy:
        score += 10
        feedback_parts.append("Oxygen (7782-44-7) found (+10)")
        
        # Check amounts (102500 lbs / 06 code & 85000 lbs / 05 code)
        max_amt = str(oxy.get('max_amount', ''))
        ave_amt = str(oxy.get('ave_amount', ''))
        if ('102500' in max_amt or '06' in max_amt) and ('85000' in ave_amt or '05' in ave_amt):
            score += 5
            
        # Check Hazards
        haz_str = str(oxy.get('hazards', '')).lower()
        if 'oxidizer' in haz_str and ('pressure' in haz_str or 'gas' in haz_str):
            score += 10
            
        # Check Storage
        storage_list = oxy.get('storage', [])
        storage_str = json.dumps(storage_list).lower()
        if 'cryogenic' in storage_str or '7' in storage_str:
            score += 5
    else:
        feedback_parts.append("Oxygen missing")

    # 4. Verify Chemical 2: Nitrous Oxide (10024-97-2)
    n2o = cas_map.get("10024-97-2")
    if n2o:
        score += 10
        feedback_parts.append("Nitrous Oxide (10024-97-2) found (+10)")
        
        # Check amounts (12500 lbs / 05 code & 8000 lbs / 04 code)
        max_amt = str(n2o.get('max_amount', ''))
        ave_amt = str(n2o.get('ave_amount', ''))
        if ('12500' in max_amt or '05' in max_amt) and ('8000' in ave_amt or '04' in ave_amt):
            score += 5
            
        # Check Hazards
        haz_str = str(n2o.get('hazards', '')).lower()
        if 'oxidizer' in haz_str and ('pressure' in haz_str or 'gas' in haz_str) and ('target' in haz_str or 'stot' in haz_str):
            score += 10
            
        # Check Storage
        storage_list = n2o.get('storage', [])
        storage_str = json.dumps(storage_list).lower()
        if 'ambient' in storage_str and ('cylinder' in storage_str or 'l' in storage_str):
            score += 5
    else:
        feedback_parts.append("Nitrous Oxide missing")

    # 5. VLM Trajectory Process Verification (Anti-Spoofing)
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        
        prompt = """You are auditing a computer agent's desktop trajectory.
        Task: Perform data entry into an application called "EPA Tier2 Submit".
        
        Look at these chronologically sampled screenshots. 
        Did the agent actually open an application resembling a database/form entry system and 
        interact with chemical records (look for inputs related to "Oxygen", "Nitrous Oxide", CAS numbers, or hazard checkboxes)?
        
        Return ONLY valid JSON:
        {
            "used_ui_application": true/false,
            "entered_chemical_data": true/false
        }
        """
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_img])
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_ui_application') and parsed.get('entered_chemical_data'):
                    score += 30
                    feedback_parts.append("VLM visual verification passed (+30)")
                else:
                    feedback_parts.append("VLM visual verification failed: Lack of UI interaction")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            # If VLM fails/unavailable, award points if programmatic is perfect to avoid penalizing agent
            if score == 60: 
                score += 30
    elif score == 60: # Fallback if VLM completely unimported
        score += 30

    # Ensure score caps at 100
    score = min(100, score)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }