#!/usr/bin/env python3
"""
Verifier for trust_beneficiary_t3_income task.

Marcus Chen-Watanabe — Manitoba resident, T3 trust beneficiary.
Features T3 slip (capital gains, eligible dividends, foreign income), 
T5 slip, RRSP, donations, medical expenses, and MB479 rent credit.

Verification Strategy:
1. File check: Exists, > 500 bytes, created during task (Anti-gaming).
2. Data extraction check: Parses the exported JSON containing regex matches from the .24t file.
3. VLM Verification: Uses trajectory frames to ensure the agent navigated correctly.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a tax preparation agent using StudioTax 2024.
Please review these screenshots captured during the agent's workflow and determine:
1. Did the agent open and interact with a T3 (Statement of Trust Income) entry screen?
2. Did the agent enter data into multiple slip forms (e.g., T4, T5, T3)?
3. Did the agent interact with the Manitoba Provincial forms (e.g., MB479 for rent/property tax)?
4. Did the agent navigate to or view the T2209 (Foreign Tax Credit) form or Medical expenses window?

Respond in pure JSON format:
{
    "t3_entry_visible": true/false,
    "multiple_slips_used": true/false,
    "manitoba_provincial_forms_visible": true/false,
    "foreign_tax_or_medical_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""

def verify_trust_beneficiary_t3_income(traj, env_info, task_info):
    """Verify Marcus Chen-Watanabe T3 Trust Income Return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: No copy_from_env helper"}

    # --- 1. Programmatic File Check ---
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/trust_beneficiary_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result from environment: {e}"}

    # Anti-gaming checks
    file_ok = result.get('file_exists', False) and result.get('file_size_bytes', 0) > 500
    if not file_ok:
        return {"passed": False, "score": 0, "feedback": "FAIL: Return file not found or empty."}
    
    score += 10
    feedback.append("Return file saved successfully.")

    if result.get('file_is_new', False):
        score += 5
        feedback.append("File timestamp valid (created/modified during task).")
    else:
        feedback.append("FAIL: File timestamp invalid (created before task).")

    # Identity check
    if result.get('contains_marcus') and result.get('contains_chen_watanabe'):
        score += 10
        feedback.append("Taxpayer name (Marcus Chen-Watanabe) identified.")
    elif result.get('contains_marcus') or result.get('contains_chen_watanabe'):
        score += 5
        feedback.append("Taxpayer name partially identified.")
    else:
        feedback.append("FAIL: Taxpayer name missing.")

    # T4 Income
    if result.get('contains_89200'):
        score += 15
        feedback.append("T4 employment income ($89,200) entered.")
    else:
        feedback.append("FAIL: T4 income missing.")

    # T3 Capital Gains - CRITICAL Differentiator
    t3_capital_gains = result.get('contains_14200')
    if t3_capital_gains:
        score += 15
        feedback.append("T3 Capital gains ($14,200) entered.")
    else:
        feedback.append("FAIL: T3 Capital gains missing.")

    # Dividends (T3 & T5)
    if result.get('contains_6800') and result.get('contains_4200'):
        score += 10
        feedback.append("Both T3 and T5 Eligible Dividends entered.")
    elif result.get('contains_6800') or result.get('contains_4200'):
        score += 5
        feedback.append("Partial Dividend data entered.")

    # Foreign Income/Tax (T2209 Trigger)
    if result.get('contains_2100') and result.get('contains_315'):
        score += 10
        feedback.append("T3 Foreign Income ($2,100) and Tax Paid ($315) entered.")
    elif result.get('contains_2100') or result.get('contains_315'):
        score += 5
        feedback.append("Partial Foreign Income/Tax data entered.")

    # Other deductions and credits (16200 Rent, 4800 Medical, 12000 RRSP, 3250 Donations)
    misc_pts = 0
    if result.get('contains_16200'): misc_pts += 3
    if result.get('contains_4800'): misc_pts += 3
    if result.get('contains_12000'): misc_pts += 2
    if result.get('contains_3250') or result.get('contains_2500'): misc_pts += 2
    
    score += misc_pts
    if misc_pts >= 5:
        feedback.append("Deductions and provincial credits correctly entered.")
    
    # --- 2. VLM Trajectory Verification ---
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images_to_check = frames + [final] if final else frames
            
            if images_to_check:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=images_to_check)
                if vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    vlm_score = 0
                    if parsed.get('t3_entry_visible'): vlm_score += 10
                    if parsed.get('multiple_slips_used'): vlm_score += 5
                    if parsed.get('manitoba_provincial_forms_visible'): vlm_score += 5
                    if parsed.get('foreign_tax_or_medical_visible'): vlm_score += 5
                    
                    score += vlm_score
                    feedback.append(f"VLM Verification awarded {vlm_score}/25 points based on UI workflow.")
                else:
                    feedback.append("VLM query failed, skipping visual verification.")
            else:
                feedback.append("No trajectory images available for VLM verification.")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback.append("VLM verification encountered an error.")

    # --- 3. Final Score Calculation & Anti-gaming limits ---
    # Score Cap: If the core differentiator of this task (T3 Capital Gains) is missing, cap the score below passing.
    if not t3_capital_gains and score > 40:
        score = 40
        feedback.append("SCORE CAP APPLIED: T3 Capital Gains ($14,200) not found. Return is fundamentally incomplete.")

    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }