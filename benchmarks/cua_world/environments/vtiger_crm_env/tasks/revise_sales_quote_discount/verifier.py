#!/usr/bin/env python3
"""
Verifier for Revise and Discount Sales Quote task.

Evaluates:
1. Was the original quote left unmodified?
2. Was the new cloned quote created with the correct subject?
3. Was the new quote's stage set to 'Reviewed'?
4. Was the 10% overall discount correctly applied to the clone?
5. VLM trajectory verification (did the agent actually use the CRM UI?).
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are auditing a computer agent working in Vtiger CRM.
The agent was tasked with duplicating a Quote, setting its discount to 10%, and saving it.

Look at these screenshots spanning the agent's workflow. 
Did the agent interact with the Vtiger CRM Quote forms? 
Specifically, can you see evidence of the Quotes list view, the Quote detail view, or the edit form with Line Items and Discount options?

Reply with a JSON object:
{
    "used_crm_ui": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_revise_quote(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_stage = metadata.get('expected_stage', 'Reviewed')
    expected_discount = float(metadata.get('expected_discount', 10.0))

    # Read the exported JSON payload
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

    db_data = result.get('db_data', {})
    
    score = 0
    feedback_parts = []

    # Criterion 1: Original Quote Intact (20 pts)
    orig_found = db_data.get('original_found', False)
    orig_discount = float(db_data.get('original_discount', 0.0))
    
    if orig_found and orig_discount == 0.0:
        score += 20
        feedback_parts.append("✅ Original quote is intact and unmodified")
    elif orig_found:
        feedback_parts.append(f"❌ Original quote was modified! Discount is {orig_discount}")
    else:
        feedback_parts.append("❌ Original quote was deleted or overwritten")

    # Criterion 2: Clone Created (30 pts)
    clone_found = db_data.get('clone_found', False)
    
    if clone_found:
        score += 30
        feedback_parts.append("✅ Cloned quote 'Revision 1' was created")
    else:
        feedback_parts.append("❌ Cloned quote 'Revision 1' was NOT found in database")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 3: Stage Updated (20 pts)
    clone_stage = db_data.get('clone_stage', '')
    if clone_stage.lower() == expected_stage.lower():
        score += 20
        feedback_parts.append("✅ Cloned quote stage is 'Reviewed'")
    else:
        feedback_parts.append(f"❌ Cloned quote stage is '{clone_stage}', expected '{expected_stage}'")

    # Criterion 4: Discount Applied (30 pts)
    clone_discount = float(db_data.get('clone_discount', 0.0))
    if abs(clone_discount - expected_discount) < 0.1:
        score += 30
        feedback_parts.append("✅ 10% discount correctly applied to clone")
    else:
        feedback_parts.append(f"❌ Cloned quote discount is {clone_discount}%, expected {expected_discount}%")

    # VLM Anti-Gaming Verification (Ensuring they didn't just curl the API)
    if score >= 70 and query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        if frames or final_img:
            images = frames + [final_img] if final_img else frames
            vlm_res = query_vlm(images=images, prompt=VERIFICATION_PROMPT)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if not parsed.get('used_crm_ui', False):
                    score = min(score, 50)  # Penalize for not using UI
                    feedback_parts.append("⚠️ VLM did not detect CRM UI interaction in trajectory.")
            else:
                logger.warning(f"VLM verification failed to parse: {vlm_res.get('error')}")

    # Final calculation
    passed = score >= 70 and clone_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }