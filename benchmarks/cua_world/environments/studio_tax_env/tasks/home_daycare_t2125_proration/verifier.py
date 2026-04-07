#!/usr/bin/env python3
"""
Verifier for home_daycare_t2125_proration task.

Evaluates the StudioTax 2024 return for Clara Yip, a home daycare provider.
Uses programmatic checks on the exported .24t file combined with VLM trajectory 
verification to ensure both outcome and workflow are correct.

Scoring (100 pts total, pass threshold 60):
- Programmatic (80 pts): File identity, T4E, T2125 Gross, Food, Home expenses
- VLM Verification (20 pts): Confirms form UI interaction (T2125 and T4E)
- Score Cap: Missing the primary T2125 Gross Income ($42,000) caps the score at 45.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_home_daycare_t2125_proration(traj, env_info, task_info):
    """Verify Clara Yip home daycare return using hybrid signals."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "ERROR: No copy_from_env helper"}

    # 1. READ PROGRAMMATIC EXPORT
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        
        # Copy from Windows Docker env
        copy_from_env("C:/Users/Docker/Desktop/home_daycare_result.json", temp_path)
        
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}

    # 2. EVALUATE PROGRAMMATIC CRITERIA (80 points total)
    
    # File Exists and Valid Size (10 pts)
    file_size = result.get('file_size_bytes', 0)
    if result.get('file_exists') and file_size > 5000:
        score += 10
        feedback.append("Return file 'clara_yip.24t' saved with adequate size")
    elif result.get('file_exists'):
        score += 5
        feedback.append(f"Return file saved but suspiciously small ({file_size} bytes)")
    else:
        feedback.append("FAIL: Return file not found")

    # Timestamp Valid (10 pts)
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid (modified during task)")
    else:
        feedback.append("FAIL: File timestamp invalid (pre-existing file)")

    # Identity and Province (10 pts)
    if result.get('contains_yip') and result.get('contains_clara') and result.get('contains_manitoba'):
        score += 10
        feedback.append("Taxpayer identity and Manitoba province correct")
    else:
        feedback.append("FAIL: Missing/incorrect taxpayer identity or province")

    # T4E Slip Income (10 pts)
    if result.get('contains_6500') and result.get('contains_650'):
        score += 10
        feedback.append("T4E EI Income ($6,500 and tax $650) found")
    else:
        feedback.append("FAIL: T4E EI Income missing")

    # T2125 Gross Income (10 pts) - Critical Check
    has_gross = result.get('contains_42000', False)
    if has_gross:
        score += 10
        feedback.append("T2125 Gross Income ($42,000) found")
    else:
        feedback.append("FAIL: T2125 Gross Income ($42,000) missing")

    # T2125 Food Expense 100% (10 pts)
    if result.get('contains_5400'):
        score += 10
        feedback.append("Daycare food expense ($5,400) found (claimed at 100%)")
    else:
        feedback.append("FAIL: Daycare food expense ($5,400) missing")

    # T2125 Business-Use-of-Home Expenses (10 pts)
    if result.get('contains_8500') and result.get('contains_3200'):
        score += 10
        feedback.append("Home expenses (mortgage $8,500, taxes $3,200) entered for proration")
    else:
        feedback.append("FAIL: Home expenses missing or incorrect")

    # Spousal Information (10 pts)
    if result.get('contains_david') and result.get('contains_65000'):
        score += 10
        feedback.append("Spouse David Yip ($65,000) entered correctly")
    else:
        feedback.append("FAIL: Spousal information missing")

    # 3. VLM TRAJECTORY VERIFICATION (20 points total)
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            images = [f for f in frames + [final] if f]
            
            if images:
                prompt = """You are evaluating an AI agent completing a tax return in StudioTax.
The agent needs to fill out a T2125 Business Income form for a Home Daycare and a T4E (Employment Insurance) form.

Examine these screenshots from the agent's workflow trajectory.
1. Did the agent open or interact with Form T2125 (Statement of Business or Professional Activities) or the "Business Use of Home" section?
2. Did the agent open or interact with the T4E slip interface?

Respond strictly in JSON format:
{
  "t2125_seen": true/false,
  "t4e_seen": true/false
}"""
                vlm_result = query_vlm(prompt=prompt, images=images)
                parsed = vlm_result.get('parsed', {})
                
                if parsed.get('t2125_seen'):
                    score += 10
                    feedback.append("VLM Verification: T2125 form interaction confirmed")
                else:
                    feedback.append("VLM Verification: T2125 interaction not detected in trajectory")
                    
                if parsed.get('t4e_seen'):
                    score += 10
                    feedback.append("VLM Verification: T4E form interaction confirmed")
                else:
                    feedback.append("VLM Verification: T4E interaction not detected in trajectory")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")
            feedback.append("VLM Verification: Skipped/Error")

    # 4. CRITICAL SCORE CAP
    # If the gross business income isn't in the file, it is a fundamentally failed return
    if not has_gross and score > 45:
        score = 45
        feedback.append("CRITICAL: Score capped at 45 because T2125 Gross Income ($42,000) was missing.")

    passed = score >= 60 and has_gross

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }