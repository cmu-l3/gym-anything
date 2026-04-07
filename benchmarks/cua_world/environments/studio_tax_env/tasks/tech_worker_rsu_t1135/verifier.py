#!/usr/bin/env python3
"""Verifier for tech_worker_rsu_t1135 task.

Jason Chen — Tech worker with RSUs.
T4 with high employment income ($185,400) and stock options (Box 38/39).
Foreign income requiring conversion: $3,500 USD -> $4,777.50 CAD.
Foreign tax withheld: $525 USD -> $716.63 CAD.
T1135 Foreign Income Verification form (USA, max funds $195k, year-end $182k).
RRSP contribution ($12,500).

Scoring (100 pts total, pass threshold 70):
  Criterion 1: File saved correctly and valid timestamp (10 pts)
  Criterion 2: Taxpayer identity present (10 pts)
  Criterion 3: T4 Base Income $185,400 (15 pts)
  Criterion 4: T4 Stock Option Deduction $22,500 (10 pts)
  Criterion 5: Converted Foreign Dividend $4,777.50 (15 pts)
  Criterion 6: Converted Foreign Tax $716.63 (10 pts)
  Criterion 7: T1135 Form Markers (USA, $182,000) (15 pts)
  Criterion 8: RRSP $12,500 (5 pts)
  Criterion 9: VLM Trajectory check for form usage (10 pts)

Anti-gaming cap: If T4 income OR converted dividend is missing, capped at 45.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating a tax preparation agent's workflow in StudioTax 2024.
Please look closely at these screenshots from the agent's trajectory.
1. Did the agent open the 'Foreign Slip' or 'Foreign Income' dialog at any point?
2. Did the agent open the 'T1135' (Foreign Income Verification Statement) form workspace?

Respond ONLY with a JSON object in this format:
{
    "used_foreign_slip": true/false,
    "used_t1135_form": true/false
}
"""

def verify_tech_worker_rsu_t1135(traj, env_info, task_info):
    """Verify Jason Chen tech worker return with T1135 and conversions."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    # ================================================================
    # Read programmatic results via copy_from_env
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/tech_worker_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File Validity & Timestamp (10 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 1000
    file_new = result.get('file_is_new')
    if file_ok and file_new:
        score += 10
        feedback.append("Return file 'jason_chen.24t' saved and timestamp valid")
    else:
        feedback.append("FAIL: Return file missing, too small, or timestamp invalid")

    # --- Criterion 2: Taxpayer Identity (10 pts) ---
    name_ok = result.get('contains_chen') and result.get('contains_jason')
    if name_ok:
        score += 10
        feedback.append("Taxpayer identity (Jason Chen) confirmed")
    else:
        feedback.append("FAIL: Taxpayer name missing")

    # --- Criterion 3: T4 Base Income (15 pts) ---
    t4_base_ok = result.get('contains_185400')
    if t4_base_ok:
        score += 15
        feedback.append("T4 employment income $185,400 found")
    else:
        feedback.append("FAIL: T4 employment income $185,400 not found")

    # --- Criterion 4: T4 Stock Option Deduction (10 pts) ---
    t4_options_ok = result.get('contains_22500')
    if t4_options_ok:
        score += 10
        feedback.append("T4 Box 39 stock option deduction $22,500 found")
    else:
        feedback.append("FAIL: T4 Box 39 amount missing")

    # --- Criterion 5: Converted Foreign Dividend (15 pts) ---
    div_converted_ok = result.get('contains_4777')
    if div_converted_ok:
        score += 15
        feedback.append("Correctly converted foreign dividend ($4,777.50 CAD) found")
    else:
        feedback.append("FAIL: Converted foreign dividend amount missing (did they forget to convert USD to CAD?)")

    # --- Criterion 6: Converted Foreign Tax (10 pts) ---
    tax_converted_ok = result.get('contains_716')
    if tax_converted_ok:
        score += 10
        feedback.append("Correctly converted foreign tax ($716.63 CAD) found")
    else:
        feedback.append("FAIL: Converted foreign tax amount missing")

    # --- Criterion 7: T1135 Form Markers (15 pts) ---
    t1135_ok = result.get('contains_usa') and result.get('contains_182000') and result.get('contains_t1135')
    if t1135_ok:
        score += 15
        feedback.append("T1135 Form data (USA, $182,000) found")
    elif result.get('contains_182000') or result.get('contains_usa'):
        score += 7
        feedback.append("Partial T1135 Form data found")
    else:
        feedback.append("FAIL: T1135 Form data missing")

    # --- Criterion 8: RRSP (5 pts) ---
    rrsp_ok = result.get('contains_12500')
    if rrsp_ok:
        score += 5
        feedback.append("RRSP $12,500 found")
    else:
        feedback.append("FAIL: RRSP missing")

    # ================================================================
    # Criterion 9: VLM Trajectory Analysis (10 pts)
    # ================================================================
    frames = sample_trajectory_frames(traj, n=6)
    vlm_score = 0
    if frames:
        vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
        if vlm_res.get('success') and vlm_res.get('parsed'):
            parsed = vlm_res['parsed']
            if parsed.get('used_foreign_slip', False):
                vlm_score += 5
                feedback.append("VLM confirmed Foreign Slip dialog usage")
            if parsed.get('used_t1135_form', False):
                vlm_score += 5
                feedback.append("VLM confirmed T1135 form workspace usage")
            
            if vlm_score == 0:
                feedback.append("VLM did not detect Foreign Slip or T1135 interface in trajectory")
        else:
            feedback.append("VLM verification failed or unparseable")
    else:
        feedback.append("No trajectory frames for VLM verification")
    
    score += vlm_score

    # ================================================================
    # Score Cap & Pass Logic
    # ================================================================
    passed = False
    if not t4_base_ok or not div_converted_ok:
        score = min(score, 45)
        feedback.append("CRITICAL: Missing core T4 income or converted foreign dividend. Score capped at 45.")
    
    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }