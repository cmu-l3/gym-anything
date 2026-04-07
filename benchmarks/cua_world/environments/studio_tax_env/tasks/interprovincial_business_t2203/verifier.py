#!/usr/bin/env python3
"""
Verifier for interprovincial_business_t2203 task.

Validates the return of Julian Rossi, focusing on the correct allocation of
business revenues and salaries between Ontario and Alberta via Form T2203.

Scoring (100 pts total, pass threshold 60):
  1. File saved & timestamp valid (15 pts)
  2. Taxpayer Name (10 pts)
  3. T4 Income $65k (10 pts)
  4. T2125 Income $240k Gross (10 pts)
  5. T2203 ON Allocation $144k (15 pts)
  6. T2203 AB Allocation $96k (15 pts)
  7. Tax Installments $35k (10 pts)
  8. VLM Trajectory Verification (15 pts)

Score cap: If T2203 allocations ($144,000 and $96,000) are missing, the score
is capped at 50 (Fail). The agent cannot just dump all income into Ontario.
"""

import json
import os
import tempfile
import logging

def verify_interprovincial_business_t2203(traj, env_info, task_info):
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy helper missing from environment."}

    # Extract JSON results from VM
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_f:
            temp_path = temp_f.name
        copy_from_env("C:/Users/Docker/Desktop/t2203_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task export result: {e}"}

    # 1. File verification (15 pts)
    file_exists = result.get('file_exists', False)
    file_new = result.get('file_is_new', False)
    file_size = result.get('file_size_bytes', 0)
    
    if file_exists and file_new and file_size > 1000:
        score += 15
        feedback.append("File 'julian_rossi.24t' successfully created/saved.")
    elif file_exists:
        score += 5
        feedback.append("File exists but timestamp or size implies issues.")
    else:
        feedback.append("FAIL: Return file not found.")

    # 2. Taxpayer Name (10 pts)
    if result.get('contains_rossi') and result.get('contains_julian'):
        score += 10
        feedback.append("Taxpayer profile (Julian Rossi) confirmed.")
    elif result.get('contains_rossi') or result.get('contains_julian'):
        score += 5
        feedback.append("Taxpayer profile partially confirmed.")
    else:
        feedback.append("FAIL: Taxpayer name not found in return.")

    # 3. T4 Employment (10 pts)
    if result.get('contains_65000'):
        score += 10
        feedback.append("T4 employment income ($65,000) found.")
    else:
        feedback.append("FAIL: T4 employment income not found.")

    # 4. T2125 Business Income (10 pts)
    if result.get('contains_240000'):
        score += 10
        feedback.append("T2125 business gross revenue ($240,000) found.")
    else:
        feedback.append("FAIL: T2125 business revenue not found.")

    # 5 & 6. Form T2203 Allocations - CRITICAL (30 pts)
    on_alloc = result.get('contains_144000', False)
    ab_alloc = result.get('contains_96000', False)
    t2203_used = result.get('contains_t2203_marker', False)

    if on_alloc and ab_alloc:
        score += 30
        feedback.append("CRITICAL: T2203 Interprovincial allocations ($144,000 ON, $96,000 AB) successfully applied.")
    elif on_alloc or ab_alloc:
        score += 10
        feedback.append("PARTIAL: Only one province's allocation was found.")
    elif t2203_used:
        score += 5
        feedback.append("T2203 Multiple Jurisdictions form invoked, but correct amounts missing.")
    else:
        feedback.append("FAIL: T2203 Multiple Jurisdictions not applied (income likely grouped in ON).")

    # 7. Tax Installments (10 pts)
    if result.get('contains_35000'):
        score += 10
        feedback.append("Tax installments paid ($35,000) applied correctly.")
    else:
        feedback.append("FAIL: Tax installments missing.")

    # 8. VLM Trajectory Verification (15 pts)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=3)
        final_frame = get_final_screenshot(traj)
        
        prompt = """
        You are verifying a tax preparation task in StudioTax 2024.
        The goal is to complete a "Multiple Jurisdictions" allocation (Form T2203) for business income.
        Look through these trajectory frames.
        1. Does the agent open the 'Multiple Jurisdictions' (T2203) form or wizard?
        2. Is there evidence of the agent entering revenue allocation between Ontario and Alberta?
        
        Respond ONLY with a JSON dictionary containing:
        {
          "t2203_interaction": true/false,
          "confidence": "high/medium/low",
          "reasoning": "Brief explanation"
        }
        """
        
        try:
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('t2203_interaction'):
                    score += 15
                    feedback.append("VLM confirmed visual interaction with Form T2203.")
                else:
                    feedback.append("VLM did not detect Form T2203 visual interaction.")
        except Exception as e:
            logging.error(f"VLM error: {e}")

    # Anti-gaming Score Cap
    key_criteria_met = on_alloc and ab_alloc
    if not key_criteria_met and score > 50:
        score = 50
        feedback.append("SCORE CAPPED: Interprovincial allocation amounts missing. T2203 is required for passing.")

    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }