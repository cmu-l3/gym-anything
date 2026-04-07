#!/usr/bin/env python3
"""Verifier for investor_carrying_charges_t5008 task.

Eleanor Vance — high-net-worth investor, Ontario.
T4 ($185,000), T5 ($14,200 dividends, $850 interest),
T5008 Dispositions (BCE $28k/$31.5k, Enbridge $45k/$38k).
Carrying Charges: Margin interest $18,250, Counsel fees $7,100.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (10 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer context (Vance/Eleanor/ON) (10 pts)
  Criterion 4: T4 Employment Income $185k (15 pts)
  Criterion 5: T5 Eligible Dividends $14.2k (10 pts)
  Criterion 6: T5008 Dispositions (15 pts)
  Criterion 7: Carrying Charges Line 22100 (20 pts)
  Criterion 8: VLM Trajectory Verification (10 pts)

Score cap: If Carrying Charges (18250 + 7100) are missing, max score 55.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investor_carrying_charges_t5008(traj, env_info, task_info):
    score = 0
    feedback = []
    
    # ALWAYS use copy_from_env to safely retrieve artifacts
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/investor_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # Criterion 1: File saved with correct name (10 pts)
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("Return file 'eleanor_vance.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # Criterion 2: Timestamp valid (10 pts)
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # Criterion 3: Taxpayer name & province (10 pts)
    name_ok = result.get('contains_vance') and result.get('contains_eleanor')
    prov_ok = result.get('contains_ontario')
    if name_ok and prov_ok:
        score += 10
        feedback.append("Taxpayer context (Name + Ontario) found")
    elif name_ok:
        score += 5
        feedback.append("Taxpayer name found, province unconfirmed")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # Criterion 4: T4 employment income $185,000 (15 pts)
    if result.get('contains_185000') and result.get('contains_62500'):
        score += 15
        feedback.append("T4 employment income $185,000 found")
    elif result.get('contains_185000'):
        score += 10
        feedback.append("T4 employment income $185,000 found (partial details)")
    else:
        feedback.append("FAIL: T4 employment income not found")

    # Criterion 5: T5 eligible dividends (10 pts)
    if result.get('contains_14200'):
        score += 10
        feedback.append("T5 eligible dividends $14,200 found")
    else:
        feedback.append("FAIL: T5 eligible dividends not found")

    # Criterion 6: T5008 Dispositions (15 pts)
    disp_values = [
        result.get('contains_28000', False),
        result.get('contains_31500', False),
        result.get('contains_45000', False),
        result.get('contains_38000', False)
    ]
    disp_count = sum(disp_values)
    if disp_count == 4:
        score += 15
        feedback.append("All T5008 disposition amounts found")
    elif disp_count > 0:
        score += int(15 * (disp_count / 4))
        feedback.append(f"Partial T5008 amounts found ({disp_count}/4)")
    else:
        feedback.append("FAIL: T5008 dispositions not found")

    # Criterion 7: Carrying Charges Line 22100 (20 pts)
    cc_interest = result.get('contains_18250', False)
    cc_fees = result.get('contains_7100', False)
    cc_total = result.get('contains_25350', False)
    
    carrying_charges_present = False
    
    if cc_total or (cc_interest and cc_fees):
        score += 20
        carrying_charges_present = True
        feedback.append("Carrying charges ($25,350 total) found")
    elif cc_interest or cc_fees:
        score += 10
        carrying_charges_present = True
        feedback.append("Partial carrying charges found")
    else:
        feedback.append("FAIL: Carrying charges not found")

    # Criterion 8: Reserved VLM Trajectory Evaluation (10 pts)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        vlm_feedback = ""
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            if final:
                images = frames + [final]
                prompt = (
                    "Did the user or agent interact with StudioTax's 'Carrying Charges', "
                    "'Schedule 4', or 'T5008' forms? Look for input fields matching "
                    "$18,250, $7,100, or securities like BCE and Enbridge. "
                    "Respond strictly in JSON with {'interacted_with_forms': true/false}."
                )
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("interacted_with_forms"):
                        score += 10
                        vlm_feedback = "VLM confirms interaction with relevant forms"
                    else:
                        vlm_feedback = "VLM did not detect interaction with relevant forms"
                else:
                    vlm_feedback = "VLM query failed"
        
        if vlm_feedback:
            feedback.append(vlm_feedback)
    except Exception as e:
        logger.warning(f"VLM evaluation failed/skipped: {e}")

    # Anti-gaming Score cap
    if not carrying_charges_present:
        if score > 55:
            score = 55
            feedback.append("SCORE CAPPED AT 55: Missing carrying charges, which is the key complexity.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }