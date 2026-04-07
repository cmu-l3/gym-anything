#!/usr/bin/env python3
"""
Verifier for hospitality_tips_cpt20_training_credit task.

Evaluates StudioTax 2024 Canadian return for a hospitality worker with:
- T4 Employment Income ($32,500)
- Direct Tips Line 10400 ($18,250)
- Form CPT20 Election to pay CPP on Tips
- T2202 Tuition ($1,800) and Canada Training Credit ($900 claim)

Verification involves reading the exported JSON data from the guest environment,
verifying presence of correctly separated amounts, and using a VLM to check trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent completing a Canadian tax return in StudioTax. 
Look at these screenshots taken during the agent's workflow.

Did the agent ever navigate to or interact with either:
1. The "Other employment income" / "Tips" entry section
2. Form CPT20 (Election to Pay Canada Pension Plan Contributions)
3. The Canada Training Credit (CTC) schedule

Respond in JSON format:
{
    "interacted_with_tips_or_cpt20": true/false,
    "interacted_with_training_credit": true/false,
    "reasoning": "brief explanation of what UI elements are visible"
}"""


def verify_hospitality_tips_cpt20_training_credit(traj, env_info, task_info):
    """Verify Mateo Vargas hospitality worker return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: No copy_from_env helper"}

    # 1. Fetch JSON result from VM
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        copy_from_env("C:/Users/Docker/Desktop/hospitality_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read exported result: {e}"}

    # 2. Score File Integrity (15 pts)
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("File 'mateo_vargas.24t' saved correctly")
    else:
        feedback.append("FAIL: Return file not found or empty")

    if result.get('file_is_new'):
        score += 5
        feedback.append("File timestamp is valid (anti-gaming)")
    else:
        feedback.append("FAIL: File timestamp predates task start")

    # 3. Taxpayer Name (10 pts)
    if result.get('contains_vargas') and result.get('contains_mateo'):
        score += 10
        feedback.append("Taxpayer name matched")
    else:
        feedback.append("FAIL: Taxpayer name missing")

    # 4. T4 Wages vs Tips Segregation (30 pts)
    # CRITICAL CHECK: Did they add tips to Box 14 incorrectly?
    if result.get('contains_50750'):
        feedback.append("CRITICAL FAIL: Tips ($18,250) were combined with T4 Box 14 ($32,500). Tips must be entered on Line 10400.")
        # Cap score for critical compliance failure
        score = min(score, 45)
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    if result.get('contains_32500'):
        score += 15
        feedback.append("T4 Wages ($32,500) entered correctly")
    
    if result.get('contains_18250'):
        score += 15
        feedback.append("Direct tips ($18,250) entered correctly")

    # 5. Union Dues (5 pts)
    if result.get('contains_520'):
        score += 5
        feedback.append("Union dues ($520) present")

    # 6. Form CPT20 (10 pts)
    if result.get('contains_cpt20'):
        score += 10
        feedback.append("CPT20 Form election data found")

    # 7. Tuition & Canada Training Credit (15 pts)
    if result.get('contains_1800') and result.get('contains_900'):
        score += 15
        feedback.append("T2202 Tuition ($1,800) and Canada Training Credit ($900) claimed")
    elif result.get('contains_1800'):
        score += 7
        feedback.append("Tuition entered but Canada Training Credit missing/incorrect")

    # 8. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    if env_info.get('query_vlm'):
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_res = env_info['query_vlm'](prompt=VLM_PROMPT, images=images)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('interacted_with_tips_or_cpt20'):
                        vlm_score += 10
                        feedback.append("VLM verified interaction with Tips/CPT20 workflow")
                    if parsed.get('interacted_with_training_credit'):
                        vlm_score += 5
                        feedback.append("VLM verified interaction with Training Credit")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback.append("VLM verification skipped/failed")
    
    score += vlm_score

    # 9. Final Evaluation
    # Must achieve 65 or higher and must have correctly separated tips vs wages
    passed = score >= 65 and not result.get('contains_50750') and result.get('contains_18250')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }