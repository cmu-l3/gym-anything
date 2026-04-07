#!/usr/bin/env python3
"""
Verifier for fhsa_qualifying_home_buyer task.

Evaluates the completion of Clara Jenkins's tax return, specifically checking:
- T4 employment income
- Aggregation of union and professional dues
- FHSA Contribution and Tax-free Withdrawal
- First-Time Home Buyers' Tax Credit (HBTC)
- Capital gains on T5008

Includes a VLM verification check over trajectory frames to ensure anti-gaming 
and confirm workflow progression.
"""

import json
import os
import tempfile
import logging

# Import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_VERIFICATION_PROMPT = """
You are verifying if a computer agent successfully worked on a Canadian tax return in StudioTax.
Analyze these trajectory frames and the final state.

Look for evidence of:
1. StudioTax software being actively used (forms, slips, personal info pages).
2. Navigation to the T4 slip, T4FHSA slip, or Schedule 15 (FHSA).
3. Evidence of entering T5008 or Capital Gains.
4. Any input of the First-Time Home Buyers' Tax Credit.

Did the agent actively work on preparing this tax return?
Respond ONLY with a JSON object:
{
    "actively_worked": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of visible actions"
}
"""

def verify_fhsa_qualifying_home_buyer(traj, env_info, task_info):
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # 1. Retrieve the exported JSON result from the container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        copy_from_env("C:/Users/Docker/Desktop/fhsa_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
            
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read exported JSON result: {e}"}

    # 2. Programmatic Verification Rules

    # Criterion 1: File saved and is substantive (10 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 500:
        score += 10
        feedback.append("Return file 'clara_jenkins.24t' saved.")
    else:
        feedback.append("FAIL: Return file not found or too small.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Timestamp validity / Anti-gaming (10 pts)
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid (created/modified during task).")
    else:
        feedback.append("FAIL: File timestamp invalid.")

    # Criterion 3: Taxpayer Profile (10 pts)
    if result.get('contains_jenkins') and result.get('contains_clara') and result.get('contains_ns'):
        score += 10
        feedback.append("Taxpayer profile (Clara Jenkins, NS) found.")
    else:
        feedback.append("FAIL: Incomplete taxpayer profile.")

    # Criterion 4: T4 Employment Income (10 pts)
    if result.get('contains_82000'):
        score += 10
        feedback.append("T4 employment income ($82,000) found.")
    else:
        feedback.append("FAIL: T4 employment income not found.")

    # Criterion 5: Aggregated Professional Dues (15 pts)
    if result.get('contains_1435'):
        score += 15
        feedback.append("Union and professional dues successfully aggregated ($1,435).")
    elif result.get('contains_950') and result.get('contains_485'):
        score += 8
        feedback.append("Dues found individually, but not properly aggregated into total.")
    else:
        feedback.append("FAIL: Professional dues not properly handled.")

    # Criterion 6: FHSA Contribution (10 pts)
    if result.get('contains_8000'):
        score += 10
        feedback.append("FHSA Contribution ($8,000) found.")
    else:
        feedback.append("FAIL: FHSA Contribution missing.")

    # Criterion 7: FHSA Qualifying Withdrawal (15 pts)
    # Critical check: Ensure they didn't put it in Box 18 (taxable), which balloons total income to 98k.
    if result.get('contains_16000'):
        if result.get('contains_98000'):
            feedback.append("CRITICAL FAIL: FHSA Withdrawal ($16,000) improperly entered as Taxable (Box 18) instead of Qualifying (Box 20).")
        else:
            score += 15
            feedback.append("FHSA Qualifying Withdrawal ($16,000) properly handled.")
    else:
        feedback.append("FAIL: FHSA Withdrawal missing.")

    # Criterion 8: First-Time Home Buyers' Amount (10 pts)
    if result.get('contains_10000'):
        score += 10
        feedback.append("First-Time Home Buyers' Tax Credit ($10,000) claimed.")
    else:
        feedback.append("FAIL: First-Time Home Buyers' amount missing.")

    # Criterion 9: T5008 Capital Gains (10 pts)
    if result.get('contains_6500') and result.get('contains_5200'):
        score += 10
        feedback.append("T5008 Capital Gain proceeds and costs correctly entered.")
    else:
        feedback.append("FAIL: T5008 Capital Gain missing or incomplete.")

    # 3. VLM Trajectory Verification
    vlm_worked = False
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(prompt=VLM_VERIFICATION_PROMPT, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    vlm_worked = parsed.get("actively_worked", False)
                    if vlm_worked:
                        feedback.append("VLM Verification: Agent actively worked on the tax return.")
                    else:
                        feedback.append(f"VLM Verification: No clear activity detected. Reasoning: {parsed.get('reasoning')}")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback.append("VLM Verification: Error occurred.")

    # Cap Score if critical FHSA error occurred or if VLM failed to verify work progression
    if result.get('contains_98000'):
        score = min(score, 50)  # Capped below passing threshold for critical tax error

    if not vlm_worked and query_vlm:
        score = min(score, 55) # Capped below passing threshold if trajectory is spoofed
        
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }