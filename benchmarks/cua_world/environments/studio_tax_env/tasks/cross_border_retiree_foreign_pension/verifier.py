#!/usr/bin/env python3
"""
Verifier for cross_border_retiree_foreign_pension task.

Validates that the dual citizen's return is properly completed with:
- Domestic pensions (CPP, OAS)
- Foreign Social Security with 15% treaty exemption
- US IRA distribution with foreign tax credit claimed on T2209
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cross_border_retiree(traj, env_info, task_info):
    """Verify Margaret Sullivan cross-border retiree return."""
    feedback = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Load the task result safely from the environment
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    prog_score = 0

    # 1. Output File and Anti-Gaming (15 pts)
    if result.get('file_exists') and result.get('file_size_bytes', 0) > 500:
        prog_score += 10
        feedback.append("Return file 'margaret_sullivan.24t' saved")
    else:
        feedback.append("FAIL: Return file not found")

    if result.get('file_is_new'):
        prog_score += 5
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # 2. Taxpayer Identification (10 pts)
    if result.get('contains_sullivan') and result.get('contains_margaret'):
        prog_score += 10
        feedback.append("Taxpayer name found")

    # 3. Canadian Pensions & Interest (15 pts)
    if result.get('contains_14200'):
        prog_score += 7
        feedback.append("CPP ($14,200) found")
    if result.get('contains_8820'):
        prog_score += 5
        feedback.append("OAS ($8,820) found")
    if result.get('contains_4350'):
        prog_score += 3
        feedback.append("T5 Interest ($4,350) found")

    # 4. US Social Security (15 pts)
    if result.get('contains_25024') or result.get('contains_21270'):
        prog_score += 15
        feedback.append("US Social Security income found")

    # 5. Canada-US Treaty Exemption - CRITICAL (15 pts)
    has_treaty = result.get('contains_3754') or result.get('contains_3753')
    if has_treaty:
        prog_score += 15
        feedback.append("15% Treaty-exempt deduction found ($3,754)")

    # 6. US IRA Distribution (15 pts)
    if result.get('contains_16320'):
        prog_score += 15
        feedback.append("US IRA distribution ($16,320) found")

    # 7. T2209 Foreign Tax Credit - CRITICAL (15 pts)
    has_ftc = result.get('contains_2448')
    if has_ftc:
        prog_score += 15
        feedback.append("Foreign tax credit ($2,448) claimed")
        
    # 8. Data-rich return check guard (15 pts)
    if result.get('file_size_bytes', 0) > 5000:
        prog_score += 15

    # Secondary VLM Verification (25 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = (
                    "Look at these screenshots of a tax preparation session in StudioTax. "
                    "Did the user navigate to the foreign income screens, T2209 Foreign Tax Credit, "
                    "or enter T4A(P)/T4A(OAS) pension slips? "
                    "Respond with a JSON object containing boolean keys 'foreign_tax_visible' "
                    "and 'slips_visible'."
                )
                vlm_result = query_vlm(images=images, prompt=prompt)
                parsed = vlm_result.get('parsed', {})
                if parsed.get('foreign_tax_visible'):
                    vlm_score += 15
                    feedback.append("VLM: Foreign tax forms visible")
                if parsed.get('slips_visible'):
                    vlm_score += 10
                    feedback.append("VLM: Pension slips visible")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    # Total Score Calculation
    total_score = prog_score + vlm_score
    normalized_score = min(int((total_score / 140.0) * 100), 100)

    # CRITICAL CAPS: 
    # Return requires correct processing of treaty exemptions/foreign tax credit
    if not has_treaty and not has_ftc:
        normalized_score = min(normalized_score, 50)
        feedback.append("CAP: Missing both treaty exemption and foreign tax credit (capped at 50)")

    passed = normalized_score >= 60 and result.get('file_exists')

    return {
        "passed": passed,
        "score": normalized_score,
        "feedback": " | ".join(feedback)
    }