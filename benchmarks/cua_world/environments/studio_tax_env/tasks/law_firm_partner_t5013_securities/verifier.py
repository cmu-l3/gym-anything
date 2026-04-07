#!/usr/bin/env python3
"""Verifier for law_firm_partner_t5013_securities task.

Marcus Chen-Whitfield — Law firm partner, Saskatchewan.
Multi-line T5013 partnership income, T5008 securities needing ACB deduction,
spousal RRSP vs personal RRSP distinction, federal political vs charitable donations.

Scoring (100 pts total, pass threshold 60):
  Programmatic Checks (75 pts max):
    1. File saved with correct name (10 pts)
    2. File is newly created/modified (5 pts)
    3. Taxpayer Name (5 pts)
    4. T5013 Business Income $165,000 (15 pts) [CRITICAL]
    5. T5008 Securities (e.g. Proceeds $28,400) (10 pts)
    6. RRSP Contributions ($19,230 or $12,000) (10 pts)
    7. Donations and Political Credits ($5,000 or $650) (10 pts)
    8. Saskatchewan + Spouse $42,000 (10 pts)
  VLM Evaluation (25 pts):
    - Visual trajectory confirmation of forms used

Score Cap: If T5013 Business Income ($165,000) is missing, score capped at 50.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_law_firm_partner_t5013_securities(traj, env_info, task_info):
    """Verify the Canadian personal tax return for the law firm partner scenario."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm_fn = env_info.get('query_vlm', query_vlm)
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # 1. Fetch the JSON evaluation results from the container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/law_firm_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result data: {e}"}

    # 2. Programmatic Verification
    
    # Check File Presence and Size (10 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 500:
        score += 10
        feedback.append("Return file 'marcus_chen_whitfield.24t' successfully saved")
    else:
        feedback.append("FAIL: Return file missing or empty")

    # Check Timestamp Anti-Gaming (5 pts)
    if result.get('file_is_new'):
        score += 5
    else:
        feedback.append("WARNING: File timestamp precedes task start")

    # Check Taxpayer Name (5 pts)
    if result.get('contains_marcus') and result.get('contains_chen'):
        score += 5
        feedback.append("Taxpayer Name confirmed")
    
    # Check T5013 Core Income (15 pts) [CRITICAL FLAG]
    has_core_income = result.get('contains_165000')
    if has_core_income:
        score += 15
        feedback.append("T5013 Business Income ($165,000) verified")
    else:
        feedback.append("FAIL: T5013 Business Income missing (Critical)")

    # Check T5008 Securities Entry (10 pts)
    if result.get('contains_28400') or result.get('contains_22100') or result.get('contains_6300'):
        score += 10
        feedback.append("T5008 Securities / ACB deduction verified")
    else:
        feedback.append("FAIL: T5008 Capital Gains data missing")

    # Check RRSP Contributions (10 pts)
    if result.get('contains_19230') and result.get('contains_12000'):
        score += 10
        feedback.append("Both Own and Spousal RRSPs verified")
    elif result.get('contains_19230') or result.get('contains_12000'):
        score += 5
        feedback.append("Partial RRSP data verified")

    # Check Donations and Political Contributions (10 pts)
    if result.get('contains_5000') and result.get('contains_650'):
        score += 10
        feedback.append("Charitable and Political Contributions verified")
    elif result.get('contains_5000') or result.get('contains_650'):
        score += 5
        feedback.append("Partial Donation/Political data verified")

    # Check Spousal Info & Province (10 pts)
    if result.get('contains_42000') and result.get('contains_sask'):
        score += 10
        feedback.append("Spouse details and SK Province verified")
    elif result.get('contains_42000'):
        score += 5

    # 3. VLM Trajectory Verification (25 pts)
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=6)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)

        prompt = """You are analyzing screenshots of an agent preparing a Canadian Tax Return in StudioTax.
Determine if the agent interacted with the following specific forms during the session:
1. Did the agent open or use the "T5013" (Partnership Income) slip window?
2. Did the agent open or use "Schedule 3" (Capital Gains) or the "T5008" slip window?
3. Did the agent use the "RRSP" section (specifically checking for Spousal RRSP options)?

Return exactly in JSON format:
{
    "t5013_seen": true/false,
    "schedule3_seen": true/false,
    "rrsp_section_seen": true/false
}
"""
        vlm_res = query_vlm_fn(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("t5013_seen"): vlm_score += 10
            if parsed.get("schedule3_seen"): vlm_score += 10
            if parsed.get("rrsp_section_seen"): vlm_score += 5
            feedback.append(f"VLM verified trajectory: +{vlm_score} pts")
        else:
            # Fallback logic if VLM is unavailable
            logger.warning("VLM failed, granting partial credit if programmatic is strong")
            if score >= 60: vlm_score = 15
    except Exception as e:
        logger.error(f"VLM evaluation error: {e}")

    score += vlm_score

    # 4. Final Score Caps
    if not has_core_income:
        score = min(score, 50)
        feedback.append("Score capped at 50 due to missing primary T5013 business income ($165,000).")

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }