#!/usr/bin/env python3
"""
Verifier for trucker_tl2_separated_parent task.

Evaluates the completion of a Canadian personal income tax return for a 
long-haul truck driver with a TL2 deduction, eligible dependant, and child care expenses.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_trucker_tl2_separated_parent(traj, env_info, task_info):
    """Verify Marcus Thibodeau's tax return (TL2 + Dependant)."""
    feedback_parts = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy from environment function not available."}

    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/trucker_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Scoring (100 points max)
    prog_score = 0
    
    # Criterion 1: File saved with correct name (10 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 500:
        prog_score += 10
        feedback_parts.append("Return file 'marcus_thibodeau.24t' saved")
    else:
        feedback_parts.append("FAIL: Return file missing or empty")

    # Criterion 2: Timestamp valid (5 pts)
    if result.get('file_is_new'):
        prog_score += 5
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("FAIL: Invalid timestamp")

    # Criterion 3: Taxpayer Name (10 pts)
    if result.get('contains_thibodeau') and result.get('contains_marcus'):
        prog_score += 10
        feedback_parts.append("Taxpayer name found")
    elif result.get('contains_thibodeau') or result.get('contains_marcus'):
        prog_score += 5
        feedback_parts.append("Taxpayer name partially found")
    else:
        feedback_parts.append("FAIL: Taxpayer name missing")

    # Criterion 4: T4 Employment Income (15 pts) - CRITICAL
    has_t4 = result.get('contains_68200', False)
    if has_t4:
        prog_score += 15
        feedback_parts.append("T4 income $68,200 found")
    else:
        feedback_parts.append("FAIL: T4 income missing")

    # Criterion 5: T5 Interest Income (5 pts)
    if result.get('contains_245'):
        prog_score += 5
        feedback_parts.append("T5 interest $245 found")

    # Criterion 6: TL2 Meals Deduction (20 pts) - CRITICAL
    has_tl2 = (result.get('contains_tl2_178') or 
               result.get('contains_tl2_12282') or 
               result.get('contains_tl2_9825') or 
               result.get('contains_tl2_9826'))
    
    if has_tl2:
        prog_score += 20
        if result.get('contains_tl2_9825') or result.get('contains_tl2_9826'):
            feedback_parts.append("TL2 long-haul deduction 80% correctly applied")
        else:
            feedback_parts.append("TL2 data found (partial validation)")
    else:
        feedback_parts.append("FAIL: TL2 meals deduction missing")

    # Criterion 7: Union Dues / RPP (5 pts)
    if result.get('contains_1560') or result.get('contains_3410'):
        prog_score += 5
        feedback_parts.append("Union dues / RPP found")

    # Criterion 8: Child Care Expenses (10 pts)
    if result.get('contains_8400') or result.get('contains_5000'):
        prog_score += 10
        feedback_parts.append("Child care expenses found")

    # Criterion 9: Medical Expenses (5 pts)
    if result.get('contains_4880') or result.get('contains_4200'):
        prog_score += 5
        feedback_parts.append("Medical expenses found")

    # Criterion 10: Dependant Info / Marital Status (5 pts)
    if result.get('contains_sophie') or result.get('contains_30400'):
        prog_score += 5
        feedback_parts.append("Dependant info / Line 30400 found")

    # Criterion 11: Manitoba Rent (10 pts)
    if result.get('contains_16800'):
        prog_score += 10
        feedback_parts.append("Manitoba rent $16,800 found")

    # 3. VLM Verification on Trajectory (25 pts max)
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """You are evaluating an agent's completion of a tax return in StudioTax 2024.
                Look at these screenshots showing the workflow.
                Verify these 3 items:
                1. Did the agent navigate to and use the TL2 form (Claim for Meals and Lodging)?
                2. Did the agent navigate to the Provincial forms (MB428/MB479) for Manitoba rent?
                3. Did the agent enter dependant child information?

                Respond strictly in valid JSON:
                {
                    "tl2_form_used": true/false,
                    "manitoba_provincial_used": true/false,
                    "dependant_entered": true/false
                }
                """
                
                vlm_result = query_vlm(images=images, prompt=prompt)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("tl2_form_used"): vlm_score += 10
                    if parsed.get("manitoba_provincial_used"): vlm_score += 8
                    if parsed.get("dependant_entered"): vlm_score += 7
                    feedback_parts.append(f"VLM verified workflow (+{vlm_score} pts)")
                else:
                    logger.warning("VLM evaluation failed.")
                    # Fallback mapping if VLM fails but program passed
                    vlm_score = int(prog_score * 0.25) 
        except Exception as e:
            logger.error(f"VLM processing error: {e}")
            vlm_score = int(prog_score * 0.25)
    else:
        # Fallback if VLM is unavailable: scale programmatic score proportionally
        vlm_score = int((prog_score / 100) * 25)

    # 4. Final Scoring Calculations
    raw_total = prog_score + vlm_score  # Max 125
    
    # Anti-gaming Score Caps
    if not has_t4:
        raw_total = min(raw_total, 40)
        feedback_parts.append("SCORE CAPPED: Missing required T4 employment income.")
    elif not has_tl2:
        raw_total = min(raw_total, 55)
        feedback_parts.append("SCORE CAPPED: Missing critical TL2 form deduction.")

    # Normalize out of 100
    final_score = min(100, int((raw_total / 125) * 100))
    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }