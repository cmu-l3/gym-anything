#!/usr/bin/env python3
"""
Verifier for rental_income_stock_options task.

Elena Vasquez — Software developer with T4, stock options, T3, T776 rental,
medical expenses, and T778 child care.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved + valid timestamp (10 pts)
  Criterion 2: Taxpayer name present (10 pts)
  Criterion 3: T4 income ($128,000) & Stock Options ($18,500 / $9,250) (15 pts)
  Criterion 4: T3 Investment income (CG $2,340, Div $890/$1,228) (10 pts)
  Criterion 5: T776 Rental Gross ($24,000) (15 pts)
  Criterion 6: T776 Rental Net/Expenses ($17,930 or $6,070) (10 pts)
  Criterion 7: Medical ($6,840) or Child Care ($8,000) (10 pts)
  Criterion 8: VLM Verification of Workflow via Trajectory (20 pts)

Score caps:
- If T4 ($128,000) is missing, score is capped at 40.
- If both T4 and T776 ($24,000) are missing, score is capped at 20.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Verification Prompt
VLM_PROMPT = """You are verifying if a computer agent successfully completed a complex tax return workflow in StudioTax.
Review these frames from the agent's screen during the task.

Did the agent navigate to and interact with at least two of the following forms:
1. T4 slip data entry (specifically checking for boxes 38/39 for stock options)
2. T776 Statement of Real Estate Rentals (Rental Income)
3. Medical Expenses schedule or T778 Child Care Expenses form

Provide your response in JSON format:
{
    "interacted_with_t4": true/false,
    "interacted_with_t776_rental": true/false,
    "interacted_with_medical_or_childcare": true/false,
    "forms_interacted_count": <integer 0-3>,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible on the screens"
}
"""

def verify_rental_income_stock_options(traj, env_info, task_info):
    """Verify Elena Vasquez complex rental + stock options return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper available."}

    # Extract JSON results from Container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/rental_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File Saved & Valid Timestamp (10 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    timestamp_ok = result.get('file_is_new')
    if file_ok and timestamp_ok:
        score += 10
        feedback.append("Return file 'elena_vasquez.24t' saved with valid timestamp.")
    elif file_ok:
        score += 5
        feedback.append("Return file found, but timestamp is invalid (pre-existing file?).")
    else:
        feedback.append("FAIL: Return file not found or empty.")

    # --- Criterion 2: Taxpayer name (10 pts) ---
    name_ok = result.get('contains_vasquez') and result.get('contains_elena')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Elena Vasquez) found.")
    elif result.get('contains_vasquez') or result.get('contains_elena'):
        score += 5
        feedback.append("Taxpayer name partially found.")
    else:
        feedback.append("FAIL: Taxpayer name not found.")

    # --- Criterion 3: T4 income & Stock Options (15 pts) ---
    t4_base_ok = result.get('contains_128000', False)
    stock_options_ok = result.get('contains_18500', False) or result.get('contains_9250', False)
    
    if t4_base_ok and stock_options_ok:
        score += 15
        feedback.append("T4 income ($128k) and stock options ($18.5k / $9.25k) found.")
    elif t4_base_ok:
        score += 10
        feedback.append("T4 income ($128k) found, but stock options missing.")
    else:
        feedback.append("FAIL: T4 income ($128,000) not found.")

    # --- Criterion 4: T3 Investment income (10 pts) ---
    t3_cg_ok = result.get('contains_2340', False)
    t3_div_ok = result.get('contains_890', False) or result.get('contains_1228', False)
    
    if t3_cg_ok and t3_div_ok:
        score += 10
        feedback.append("T3 capital gains and dividends found.")
    elif t3_cg_ok or t3_div_ok:
        score += 5
        feedback.append("Partial T3 investment data found.")
    else:
        feedback.append("FAIL: T3 investment income not found.")

    # --- Criterion 5: T776 Rental Gross (15 pts) ---
    rental_gross_ok = result.get('contains_24000', False)
    if rental_gross_ok:
        score += 15
        feedback.append("T776 gross rental income ($24,000) found.")
    else:
        feedback.append("FAIL: T776 gross rental income not found.")

    # --- Criterion 6: T776 Rental Net/Expenses (10 pts) ---
    rental_exp_ok = result.get('contains_17930', False)
    rental_net_ok = result.get('contains_6070', False)
    if rental_exp_ok or rental_net_ok:
        score += 10
        feedback.append("T776 rental expenses/net amount found.")
    else:
        feedback.append("FAIL: T776 rental expenses not found.")

    # --- Criterion 7: Medical or Child Care (10 pts) ---
    medical_ok = result.get('contains_6840', False)
    childcare_ok = result.get('contains_8000', False)
    if medical_ok and childcare_ok:
        score += 10
        feedback.append("Medical expenses ($6,840) and Child Care ($8,000) found.")
    elif medical_ok or childcare_ok:
        score += 5
        feedback.append("Partial medical or child care data found.")
    else:
        feedback.append("FAIL: Medical/Child Care expenses not found.")

    # --- Criterion 8: VLM Verification of Trajectory (20 pts) ---
    vlm_pts = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=images)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    forms_count = parsed.get("forms_interacted_count", 0)
                    if forms_count >= 2:
                        vlm_pts = 20
                        feedback.append("VLM confirmed multiple complex forms were navigated to.")
                    elif forms_count == 1:
                        vlm_pts = 10
                        feedback.append("VLM confirmed partial interaction with tax forms.")
                    else:
                        feedback.append("VLM did not observe interaction with requested forms.")
                else:
                    feedback.append(f"VLM query failed: {vlm_res.get('error')}")
                    vlm_pts = 10  # Partial default if VLM errors out
            else:
                feedback.append("No trajectory images available for VLM.")
        except Exception as e:
            logger.error(f"VLM verification exception: {e}")
            feedback.append("VLM verification exception occurred.")
    else:
        feedback.append("VLM unavailable - skipping visual verification.")
        vlm_pts = 10 # Grace point if completely unavailable

    score += vlm_pts

    # --- Apply Caps for Critical Misses ---
    if not t4_base_ok and not rental_gross_ok:
        score = min(score, 20)
        feedback.append("CRITICAL: Both T4 and Rental income are missing. Score capped at 20.")
    elif not t4_base_ok:
        score = min(score, 40)
        feedback.append("CRITICAL: Primary T4 income missing. Score capped at 40.")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }