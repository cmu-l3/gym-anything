#!/usr/bin/env python3
"""Verifier for apprentice_electrician_tools_hbp task.

Marcus Chen — Apprentice Electrician, Manitoba.
Validates the correct entry of:
- T4 ($56,200) with Union Dues ($1,680) and Box 56 tools ($2,840)
- Tradesperson Tools Deduction Line 22900 (threshold $1,472)
- T4E Employment Insurance Benefits ($4,320)
- T4A Apprenticeship Grant ($3,000)
- First-Time Home Buyer's Tax Credit ($10,000)
- RRSP ($3,500) and MB479 Rent ($10,800)
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a computer agent successfully completed a tax return in StudioTax 2024.

Analyze these trajectory frames and the final screenshot to determine:
1. Did the agent navigate through the T4 slip screen?
2. Did the agent navigate through the T4E (Employment Insurance) slip screen?
3. Did the agent navigate to the Tradesperson's Tools Deduction form or Provincial (MB479) forms?
4. Is there evidence that the agent successfully worked within StudioTax and didn't just stay on the desktop?

Respond in JSON format:
{
    "used_studiotax": true/false,
    "accessed_t4": true/false,
    "accessed_t4e": true/false,
    "accessed_deductions_or_provincial": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_apprentice_electrician(traj, env_info, task_info):
    """Verify Marcus Chen apprentice electrician return."""
    score = 0
    feedback = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # 1. Retrieve the programmatic result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/apprentice_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}

    # --- Programmatic Scoring (80 points total) ---
    
    # Criterion 1: File saved with correct name and reasonable size (10 pts)
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("File 'marcus_chen.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # Criterion 2: Timestamp valid - prevents pre-existing files (5 pts)
    if result.get('file_is_new'):
        score += 5
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # Criterion 3: Taxpayer Name (10 pts)
    if result.get('contains_chen') and result.get('contains_marcus'):
        score += 10
        feedback.append("Taxpayer name found")
    elif result.get('contains_chen') or result.get('contains_marcus'):
        score += 5
        feedback.append("Taxpayer name partially found")

    # Criterion 4: T4 Income $56,200 (15 pts)
    t4_income_present = result.get('contains_56200', False)
    if t4_income_present:
        score += 15
        feedback.append("T4 employment income $56,200 found")
    else:
        feedback.append("FAIL: T4 employment income not found")

    # Criterion 5: T4E EI Benefits $4,320 (15 pts) - Crucial discriminator
    if result.get('contains_4320'):
        score += 15
        feedback.append("T4E EI benefits $4,320 found")
    else:
        feedback.append("FAIL: T4E EI benefits not found")

    # Criterion 6: T4A Grant $3,000 (10 pts)
    if result.get('contains_3000'):
        score += 10
        feedback.append("T4A apprenticeship grant $3,000 found")
    else:
        feedback.append("FAIL: T4A grant not found")

    # Criterion 7: Credits and Deductions (15 pts distributed)
    credits_score = 0
    if result.get('contains_1680'): credits_score += 3        # Union Dues
    if result.get('contains_2840') or result.get('contains_1472'): credits_score += 4 # Tools
    if result.get('contains_10000'): credits_score += 3       # HBTC
    if result.get('contains_3500'): credits_score += 2        # RRSP
    if result.get('contains_mb') and result.get('contains_10800'): credits_score += 3 # MB479 Rent
    
    score += credits_score
    if credits_score > 0:
        feedback.append(f"Credits and deductions partial match (+{credits_score} pts)")

    # --- VLM Verification (20 points total) ---
    vlm_query_func = env_info.get('query_vlm')
    if vlm_query_func:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            if images:
                vlm_res = vlm_query_func(images=images, prompt=VLM_PROMPT)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('used_studiotax'): score += 5
                    if parsed.get('accessed_t4'): score += 5
                    if parsed.get('accessed_t4e'): score += 5
                    if parsed.get('accessed_deductions_or_provincial'): score += 5
                    feedback.append(f"VLM verification applied (+{min(20, score)} visual pts)")
                else:
                    feedback.append("VLM query failed, skipping visual pts")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            feedback.append("VLM verification errored out")
    else:
        # If VLM is not available, we prorate the programmatic score to 100
        score = int(score * (100.0 / 80.0))
        feedback.append("VLM not available, score prorated to 100")

    # --- Score Caps and Final Evaluation ---
    # Core return logic: If T4 employment income is totally missing, cap at 50 to prevent passing
    if not t4_income_present:
        score = min(score, 50)
        feedback.append("CAP: Core T4 employment income missing. Score capped at 50.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }