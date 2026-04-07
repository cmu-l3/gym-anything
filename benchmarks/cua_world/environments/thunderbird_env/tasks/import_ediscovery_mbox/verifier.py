#!/usr/bin/env python3
"""
Verifier for the Import eDiscovery Archive and Extract Evidence task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_ediscovery_mbox(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Safely copy over the exported results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # CRITERION 1: MBOX Archive Extracted (10 pts)
    if result.get("mbox_extracted"):
        score += 10
        feedback.append("[+10] Archive extracted successfully.")
    else:
        feedback.append("[0] Archive was not extracted outside of the ZIP.")
        
    # CRITERION 2: Thunderbird Indexed (40 pts)
    if result.get("msf_exists"):
        score += 40
        feedback.append("[+40] Thunderbird successfully indexed the MBOX (MSF file created).")
    else:
        feedback.append("[0] Thunderbird index (MSF) not found. Process incomplete.")
        
    # CRITERION 3: Target PDF Extracted & Anti-gaming (20 pts)
    pdf_valid = False
    if result.get("pdf_exists"):
        if result.get("pdf_created_during_task"):
            score += 20
            feedback.append("[+20] PDF extracted to the correct directory during task session.")
            pdf_valid = True
        else:
            feedback.append("[0] PDF exists but was NOT created during the task (anti-gaming check failed).")
    else:
        feedback.append("[0] Target PDF (fw9.pdf) not found in Case_Files directory.")
        
    # CRITERION 4: Hash Match (30 pts)
    hash_matched = False
    actual_hash = result.get("pdf_hash", "")
    expected_hash = result.get("expected_hash", "expected")
    
    if pdf_valid and actual_hash and actual_hash == expected_hash:
        score += 30
        feedback.append("[+30] Extracted PDF hash perfectly matches the ground truth attachment.")
        hash_matched = True
    elif pdf_valid:
        feedback.append(f"[0] Extracted PDF hash does not match (corrupted or wrong file). Actual: {actual_hash[:8]}...")
        
    # Trajectory VLM verification check (Optional context addition)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying an agent completing an eDiscovery extraction task.
The agent needs to open Thunderbird and locate an email with subject 'Fwd: Executed W-9 Form for Project'.
Look at these chronological screenshots. Did the agent open Thunderbird and interact with the target email?
Respond in JSON format:
{
    "thunderbird_visible": true/false,
    "target_email_opened": true/false,
    "confidence": "high/medium/low"
}"""
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success") and vlm_res.get("parsed"):
                parsed = vlm_res["parsed"]
                if parsed.get("target_email_opened"):
                    feedback.append("[VLM] Verified visual interaction with target email.")
    except Exception as e:
        logger.info(f"VLM context skipped: {e}")
        
    passed = (score >= 90) and pdf_valid and hash_matched
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }