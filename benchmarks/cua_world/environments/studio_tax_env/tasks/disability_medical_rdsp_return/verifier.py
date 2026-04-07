#!/usr/bin/env python3
"""Verifier for disability_medical_rdsp_return task.

Marcus Chen-Williams — Return with approved Disability Tax Credit (DTC),
taxable RDSP (Box 28 = $4,500), non-taxable RDSP (Box 131 = $3,000, must be excluded),
medical expenses ($14,280), and spouse income ($68,000).

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (10 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (5 pts)
  Criterion 4: T4 employment income $28,500 present (10 pts)
  Criterion 5: Disability Tax Credit flagged/marker present (20 pts)
  Criterion 6: T4A RDSP taxable $4,500 present & $7,500 NOT present (10 pts)
  Criterion 7: Medical expenses $14,280 present (10 pts)
  Criterion 8: Spouse Elena & $68,000 income present (5 pts)
  20 pts reserved for VLM trajectory evaluation (Checking UI boxes/panels)

Score caps & penalties:
- If DTC NOT flagged, score is capped at 45.
- If T4 ($28,500) is missing, score is capped at 50.
- If $7,500 is found (RDSP over-reported), apply a -10 point penalty.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying if a tax preparer agent successfully completed a Canadian tax return using StudioTax 2024.

TASK: File a return for Marcus Chen-Williams, featuring an approved Disability Tax Credit, RDSP income, and Medical Expenses.

Look at the provided trajectory frames (screenshots of the agent's process) and determine:
1. Did the agent navigate to the Personal Information / Profile section and check a box indicating the taxpayer has an approved Disability Tax Credit (T2201)?
2. Did the agent open the T4A entry screen?
3. Did the agent enter medical expenses into the medical expenses schedule/wizard?
4. Is there evidence that the agent avoided entering the non-taxable $3,000 from Box 131 into a taxable income field?

Respond in JSON format:
{
    "dtc_checkbox_interacted": true/false,
    "t4a_screen_visible": true/false,
    "medical_expenses_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""

def verify_disability_medical_rdsp_return(traj, env_info, task_info):
    """Verify Marcus Chen-Williams disability & RDSP return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    # 1. Retrieve Programmatic JSON results
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/disability_task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result from environment: {e}"}

    # 2. Evaluate Programmatic Criteria
    
    # Criterion 1: File saved (10 pts)
    file_ok = result.get('file_exists', False) and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("FAIL: Return file not found or too small.")

    # Criterion 2: Timestamp (10 pts)
    if result.get('file_is_new', False):
        score += 10
        feedback.append("File timestamp is valid.")
    else:
        feedback.append("FAIL: File was not created/modified during the task.")

    # Criterion 3: Name (5 pts)
    if result.get('contains_marcus') and result.get('contains_chen'):
        score += 5
        feedback.append("Taxpayer name found.")
    else:
        feedback.append("FAIL: Taxpayer name missing.")

    # Criterion 4: T4 Income (10 pts)
    has_t4 = result.get('contains_28500', False)
    if has_t4:
        score += 10
        feedback.append("T4 employment income ($28,500) entered.")
    else:
        feedback.append("FAIL: T4 employment income missing.")

    # Criterion 5: Disability Tax Credit Flag (20 pts)
    has_dtc = result.get('contains_dtc_marker', False)
    if has_dtc:
        score += 20
        feedback.append("CRITICAL: Disability Tax Credit (DTC) marker found.")
    else:
        feedback.append("FAIL: DTC marker not found. This is a critical error.")

    # Criterion 6: T4A RDSP Taxable amount & Exclusion (10 pts)
    has_taxable_rdsp = result.get('contains_4500', False)
    has_nontaxable_error = result.get('contains_7500', False)
    if has_taxable_rdsp and not has_nontaxable_error:
        score += 10
        feedback.append("T4A RDSP taxable income ($4,500) correct and non-taxable portion excluded.")
    elif has_taxable_rdsp and has_nontaxable_error:
        score += 5
        feedback.append("T4A RDSP entered, but total income may be over-reported ($7,500 marker found).")
    else:
        feedback.append("FAIL: T4A RDSP taxable income missing.")

    # Criterion 7: Medical Expenses (10 pts)
    has_medical = result.get('contains_14280', False) or result.get('contains_med_components', False)
    if has_medical:
        score += 10
        feedback.append("Medical expenses ($14,280 or components) found.")
    else:
        feedback.append("FAIL: Medical expenses missing.")

    # Criterion 8: Spouse Data (5 pts)
    if result.get('contains_elena') and result.get('contains_68000'):
        score += 5
        feedback.append("Spouse data (Elena, $68,000) found.")
    else:
        feedback.append("FAIL: Spouse data missing/incorrect.")


    # 3. Penalties & Score Caps (Pre-VLM)
    if has_nontaxable_error:
        score -= 10
        feedback.append("PENALTY: -10 pts for improperly claiming non-taxable RDSP grant as income.")

    if not has_dtc and score > 45:
        score = 45
        feedback.append("CAP APPLIED: Score capped at 45 because Disability Tax Credit was not flagged.")
    elif not has_t4 and score > 50:
        score = 50
        feedback.append("CAP APPLIED: Score capped at 50 because core T4 employment income is missing.")

    # 4. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    
                    if parsed.get("dtc_checkbox_interacted", False):
                        vlm_score += 10
                        feedback.append("VLM confirmed DTC checkbox interaction.")
                    
                    if parsed.get("medical_expenses_visible", False) or parsed.get("t4a_screen_visible", False):
                        vlm_score += 10
                        feedback.append("VLM confirmed Medical/T4A screens used.")
                        
                else:
                    feedback.append("VLM query failed or returned no parsable data.")
        except Exception as e:
            logger.error(f"VLM evaluation error: {e}")
            feedback.append("VLM evaluation encountered an error.")
    
    score += vlm_score

    # Ensure score bounds
    score = max(0, min(100, score))
    passed = score >= 60 and has_dtc and has_t4

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }