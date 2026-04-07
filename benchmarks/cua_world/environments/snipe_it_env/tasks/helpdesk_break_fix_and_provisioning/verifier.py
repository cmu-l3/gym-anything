#!/usr/bin/env python3
"""
Verifier for helpdesk_break_fix_and_provisioning task.

Uses robust multi-signal verification including deterministic database querying and anti-gaming application log validation. 
Includes fallback VLM trajectory validation.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/helpdesk_task_result.json"

def verify_helpdesk_queue(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
        
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []
    
    # 1. LAP-DT-01 Checked In (10 pts)
    lap_dt_assigned = result.get('lap_dt_assigned', '')
    logs = result.get('logs', {})
    
    if lap_dt_assigned == 'NULL' or lap_dt_assigned == '0' or not lap_dt_assigned:
        if logs.get('checkin_lap_dt', 0) > 0:
            score += 10
            feedback.append("LAP-DT-01 successfully checked in via UI (+10)")
        else:
            feedback.append("LAP-DT-01 checked in, but missing action log (Anti-Gaming Triggered! No points) (+0)")
    else:
        feedback.append(f"LAP-DT-01 still assigned to user (+0)")

    # 2. LAP-DT-01 Status Update (15 pts)
    status = result.get('lap_dt_status', '')
    if "Out for Repair" in status:
        score += 15
        feedback.append("LAP-DT-01 status updated to Out for Repair (+15)")
    else:
        feedback.append(f"LAP-DT-01 status is '{status}', expected Out for Repair (+0)")
        
    # 3. LAP-DT-01 Notes Updated (10 pts)
    notes = result.get('lap_dt_notes', '')
    if "Cracked screen" in notes:
        score += 10
        feedback.append("LAP-DT-01 notes correctly updated (+10)")
    else:
        feedback.append("LAP-DT-01 notes missing 'Cracked screen' (+0)")
        
    # 4. LAP-SPARE-01 Checked Out (15 pts)
    lap_spare = result.get('lap_spare_assigned', '')
    dt_id = result.get('dtaylor_id', '-1')
    if str(lap_spare) == str(dt_id):
        if logs.get('checkout_lap_spare', 0) > 0:
            score += 15
            feedback.append("LAP-SPARE-01 assigned to David Taylor via UI (+15)")
        else:
            feedback.append("LAP-SPARE-01 assigned, but missing action log (Anti-Gaming Triggered! No points) (+0)")
    else:
        feedback.append("LAP-SPARE-01 not assigned to David Taylor (+0)")

    # 5. MON-SPARE-01 Checked Out (15 pts)
    mon_spare = result.get('mon_spare_assigned', '')
    mg_id = result.get('mgarcia_id', '-1')
    if str(mon_spare) == str(mg_id):
        if logs.get('checkout_mon_spare', 0) > 0:
            score += 15
            feedback.append("MON-SPARE-01 assigned to Maria Garcia via UI (+15)")
        else:
            feedback.append("MON-SPARE-01 assigned, but missing action log (Anti-Gaming Triggered! No points) (+0)")
    else:
        feedback.append("MON-SPARE-01 not assigned to Maria Garcia (+0)")
        
    # 6. Accessory Checked Out (15 pts)
    acc_assigned = result.get('acc_assigned', 0)
    if acc_assigned > 0:
        if logs.get('checkout_mouse', 0) > 0:
            score += 15
            feedback.append("Mouse accessory checked out to John Smith via UI (+15)")
        else:
            feedback.append("Mouse assigned, but missing action log (Anti-Gaming Triggered! No points) (+0)")
    else:
        feedback.append("Mouse accessory not assigned to John Smith (+0)")
        
    # 7. VLM Verification (Bonus 20 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        frames = []
        if isinstance(traj, list) and len(traj) > 0:
            # Safely extract images from trajectory
            for step in traj:
                obs = step.get('observation', {})
                if isinstance(obs, dict) and 'image' in obs:
                    frames.append(obs['image'])
        
        if len(frames) > 0:
            # Subsample last 3 frames to limit prompt size 
            sample_frames = frames[-3:] if len(frames) >= 3 else frames
            prompt = """You are verifying an IT asset management task in Snipe-IT.
Look at these sequential screenshots from the agent's desktop interaction. 
Do these frames show the Snipe-IT web application being interacted with, particularly indicating that asset/accessory checkouts or profile navigation occurred? 
Respond in JSON format: {"ui_interaction_visible": true/false}."""
            
            try:
                vlm_res = query_vlm(prompt=prompt, images=sample_frames)
                if vlm_res.get('success') and vlm_res.get('parsed', {}).get('ui_interaction_visible', False):
                    vlm_score = 20
                    feedback.append("VLM Verification: UI interaction visible from trajectory (+20)")
                else:
                    feedback.append("VLM Verification: UI interaction not confirmed from trajectory (+0)")
            except Exception as e:
                feedback.append(f"VLM Verification error: {str(e)} (+0)")
        else:
            vlm_score = 20
            feedback.append("VLM Verification: No frames available, giving default points (+20)")
    else:
        vlm_score = 20
        feedback.append("VLM Verification: VLM query function not available, giving default points (+20)")
        
    score += vlm_score

    # To pass, they must secure at least an 80/100 (which guarantees the bulk of the tickets were solved properly).
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }