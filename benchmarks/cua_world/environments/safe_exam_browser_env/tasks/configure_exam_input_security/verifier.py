#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_exam_input_security(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    config_exists = result.get('config_exists', False)
    attributes = result.get('attributes', {})
    
    # Check core requirements
    if config_exists:
        score += 20
        feedback_parts.append("Exam configuration created")
        
        # 1. Check spell check disabled
        spell_check = attributes.get('allowSpellCheck', '').lower()
        if spell_check in ['false', '0']:
            score += 35
            feedback_parts.append("Spell check disabled")
        elif spell_check:
            feedback_parts.append(f"Spell check set to '{spell_check}' (expected false)")
        else:
            feedback_parts.append("Spell check attribute not found or unchanged")
            
        # 2. Check single app mode enabled
        single_app = str(attributes.get('allowSingleAppMode', '') or 
                         attributes.get('singleAppMode', '') or 
                         attributes.get('useSingleAppMode', '')).lower()
                         
        if single_app in ['true', '1']:
            score += 35
            feedback_parts.append("Single app mode enabled")
        elif single_app:
            feedback_parts.append(f"Single app mode set to '{single_app}' (expected true)")
        else:
            feedback_parts.append("Single app mode attribute not found or unchanged")
    else:
        feedback_parts.append("Exam configuration 'Creative Writing Midterm' not found")

    # Fallback / enhancement via VLM Trajectory Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if final:
            images = frames + [final]
            prompt = "Look at these screenshots. Is the user navigating through Safe Exam Browser Server to edit SEB Settings like 'Browser' features or 'Security' features? Answer YES or NO."
            vlm_res = query_vlm(images=images, prompt=prompt)
            
            text = ""
            if isinstance(vlm_res, dict):
                text = str(vlm_res.get('answer', vlm_res)).lower()
            else:
                text = str(vlm_res).lower()
                
            if 'yes' in text:
                score += 10
                feedback_parts.append("VLM confirmed SEB Settings access")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Pass threshold is 90 (Requires Config Exists + Spell Check Disabled + Single App Mode Enabled)
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }