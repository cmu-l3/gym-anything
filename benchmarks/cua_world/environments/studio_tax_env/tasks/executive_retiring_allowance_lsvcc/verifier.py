#!/usr/bin/env python3
"""Verifier for executive_retiring_allowance_lsvcc task.

Richard Vance — Executive, SK resident.
T4 (Box 66: $28k, Box 67: $72k), T4PS, LSVCC ($5k), Political ($400).
Critical complexity: $28k RRSP transfer under 60(j.1) must be separated 
from the $5k regular RRSP contribution.

Scoring (100 pts total, pass threshold 70):
  Criterion 1: File created and identity valid (10 pts)
  Criterion 2: T4 Retiring Allowances (28k + 72k) (20 pts)
  Criterion 3: T4PS Income elements (15 pts)
  Criterion 4: Section 60(j.1) Transfer validation (20 pts)
  Criterion 5: T5006 LSVCC Credit (15 pts)
  Criterion 6: Political Contribution (10 pts)
  Criterion 7: VLM Process Evidence (10 pts)

Score cap: If the $28k transfer is combined into $33k, the score is capped at 55.
"""

import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_executive_retiring_allowance(traj, env_info, task_info):
    """Verify Richard Vance's retiring allowance return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # Load result JSON
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/tmp/executive_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result JSON: {e}"}

    # --- Criterion 1: Identity and File Validation (10 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if not file_ok:
        return {"passed": False, "score": 0, "feedback": "FAIL: Return file not found or too small."}
    
    if not result.get('file_is_new'):
        feedback.append("WARNING: File timestamp invalid (existed prior to task start).")
    
    name_ok = result.get('contains_vance') and result.get('contains_richard')
    prov_ok = result.get('contains_sk')
    
    if name_ok and prov_ok:
        score += 10
        feedback.append("Taxpayer identity (Richard Vance, SK) found.")
    elif name_ok:
        score += 5
        feedback.append("Taxpayer name found, but province (SK) missing.")
    else:
        feedback.append("FAIL: Taxpayer name missing.")

    # --- Criterion 2: T4 Retiring Allowances (20 pts) ---
    box66 = result.get('contains_28000')
    box67 = result.get('contains_72000')
    if box66 and box67:
        score += 20
        feedback.append("T4 Box 66 ($28,000) and Box 67 ($72,000) found.")
    elif box66 or box67:
        score += 10
        feedback.append("Partial T4 retiring allowances found.")
    else:
        feedback.append("FAIL: T4 retiring allowances not found.")

    # --- Criterion 3: T4PS Income (15 pts) ---
    t4ps_items = sum([result.get('contains_1500', False), 
                      result.get('contains_2100', False), 
                      result.get('contains_800', False)])
    if t4ps_items == 3:
        score += 15
        feedback.append("T4PS income entries ($1,500, $2,100, $800) found.")
    elif t4ps_items > 0:
        score += (t4ps_items * 5)
        feedback.append(f"Partial T4PS income entries found ({t4ps_items}/3).")
    else:
        feedback.append("FAIL: T4PS income entries not found.")

    # --- Criterion 4: Section 60(j.1) Transfer vs Regular RRSP (20 pts + CAP CHECK) ---
    # The agent must keep the $28k transfer and $5k regular separate. 
    # If they typed $33,000 into the RRSP field, they failed the transfer rule.
    combined_error = result.get('contains_33000', False)
    reg_rrsp = result.get('contains_5000', False)
    
    if combined_error:
        feedback.append("CRITICAL FAIL: Combined RRSP of $33,000 found. Failed to properly designate 60(j.1) transfer.")
        transfer_success = False
    elif box66 and reg_rrsp:
        score += 20
        transfer_success = True
        feedback.append("Section 60(j.1) transfer separated correctly from regular RRSP.")
    else:
        transfer_success = False
        feedback.append("FAIL: RRSP contributions / transfers missing or incomplete.")

    # --- Criterion 5: LSVCC Credit (15 pts) ---
    if result.get('contains_5000', False):
        score += 15
        feedback.append("LSVCC T5006 entry ($5,000) found.")
    else:
        feedback.append("FAIL: LSVCC entry not found.")

    # --- Criterion 6: Political Contribution (10 pts) ---
    if result.get('contains_400', False):
        score += 10
        feedback.append("Political contribution ($400) found.")
    else:
        feedback.append("FAIL: Political contribution not found.")

    # --- Criterion 7: VLM Process Evidence (10 pts) ---
    # Use VLM on trajectory to verify interaction with the specific UI dialogs
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    images_to_check = frames + [final_frame] if final_frame else frames
    
    vlm_prompt = """You are evaluating a tax preparer agent.
Look at these screenshots of StudioTax 2024.
Did the agent navigate to and open EITHER:
1. The 'RRSP / PRPP / SPP Transfers' section (Schedule 7)
2. The 'Labour-Sponsored Funds' (T5006) form
Respond with a JSON object containing a boolean 'opened_special_forms'."""
    
    vlm_result = query_vlm(images=images_to_check, prompt=vlm_prompt)
    if vlm_result.get("success") and vlm_result.get("parsed", {}).get("opened_special_forms", False):
        score += 10
        feedback.append("VLM confirmed interaction with special forms UI.")
    else:
        feedback.append("VLM could not confirm interaction with special forms UI.")

    # --- Check Caps and Thresholds ---
    if not transfer_success:
        score = min(score, 55)
        feedback.append("SCORE CAPPED AT 55: Failure to correctly structure the 60(j.1) transfer.")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }