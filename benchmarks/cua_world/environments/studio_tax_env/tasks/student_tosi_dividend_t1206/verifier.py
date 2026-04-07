#!/usr/bin/env python3
"""
Verifier for student_tosi_dividend_t1206 task.

Chloe Tremblay — University student with employment, scholarship, and private dividend.
Crucially, the dividend ($25,000) is subject to the Tax on Split Income (TOSI) and 
requires the agent to mark the T5 slip appropriately so it populates Form T1206.

Scoring (100 pts total, pass threshold 70):
  Criterion 1: File saved correctly and new (15 pts)
  Criterion 2: Taxpayer name present (5 pts)
  Criterion 3: T4 employment income $8,500 (10 pts)
  Criterion 4: T2202 Tuition $7,500 & T4A $5,000 (10 pts)
  Criterion 5: T5 Dividend $25,000 present (10 pts)
  Criterion 6: TOSI / T1206 flag activated (30 pts) -> CRITICAL
  Criterion 7: VLM verification of agent workflow (20 pts)

Score cap: If the T5 dividend is entered BUT the TOSI rules are not applied, 
the score is severely capped, as this gives the taxpayer thousands of dollars 
in inappropriate tax savings.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_student_tosi_dividend_t1206(traj, env_info, task_info):
    score = 0
    feedback = []
    
    # 1. Secure file transfer using copy_from_env (NO exec_in_env)
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/tmp/tosi_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result export: {e}"}

    # 2. File State Evaluation
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok and result.get('file_is_new'):
        score += 15
        feedback.append("✅ Return file 'chloe_tremblay.24t' saved and timestamp verified.")
    else:
        feedback.append("❌ FAIL: Return file missing, blank, or generated before task start.")

    # 3. Personal Info Evaluation
    if result.get('contains_tremblay') and result.get('contains_chloe'):
        score += 5
        feedback.append("✅ Taxpayer name found.")
    else:
        feedback.append("❌ FAIL: Taxpayer name incorrect or missing.")

    # 4. Standard Income & Deductions Evaluation
    if result.get('contains_8500'):
        score += 10
        feedback.append("✅ T4 employment income ($8,500) found.")
    else:
        feedback.append("❌ FAIL: T4 employment income missing.")

    if result.get('contains_7500') and result.get('contains_5000'):
        score += 10
        feedback.append("✅ T2202 tuition ($7,500) and T4A scholarship ($5,000) found.")
    elif result.get('contains_7500') or result.get('contains_5000'):
        score += 5
        feedback.append("⚠️ Partial student tax data found.")
    else:
        feedback.append("❌ FAIL: Student tax data missing.")

    # 5. T5 and TOSI (CRITICAL) Evaluation
    t5_entered = result.get('contains_25000')
    tosi_applied = result.get('contains_tosi')

    if t5_entered:
        score += 10
        feedback.append("✅ T5 dividend ($25,000) found.")
    else:
        feedback.append("❌ FAIL: T5 dividend missing.")

    if tosi_applied:
        score += 30
        feedback.append("✅ CRITICAL: Tax on Split Income (TOSI) flag successfully applied.")
    elif t5_entered and not tosi_applied:
        feedback.append("❌ CRITICAL FAIL: T5 entered but TOSI rules were NOT applied. This causes massive tax underpayment!")

    # 6. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames

            if images:
                prompt = (
                    "You are evaluating a desktop AI agent performing a tax workflow in StudioTax. "
                    "Look at these trajectory frames and determine: "
                    "1. Is StudioTax explicitly open and being used for data entry? "
                    "2. Are there any blocking application errors or crashed windows? "
                    "Respond with valid JSON only: {\"studiotax_used\": true/false, \"no_errors\": true/false}"
                )
                vlm_result = query_vlm(prompt=prompt, images=images)
                
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("studiotax_used"):
                        vlm_score += 10
                        feedback.append("✅ VLM: StudioTax usage confirmed.")
                    if parsed.get("no_errors"):
                        vlm_score += 10
                        feedback.append("✅ VLM: No blocking errors detected.")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")

    score += vlm_score

    # 7. Cap and Pass Evaluation
    if t5_entered and not tosi_applied:
        # Prevents passing if the anti-avoidance rule is missed, regardless of other points.
        score = min(score, 60)
        feedback.append("⚠️ SCORE CAPPED AT 60: Failing to apply TOSI is a critical non-compliance error.")

    # Must hit 70 total and explicitly have the TOSI rules applied
    passed = score >= 70 and t5_entered and tosi_applied

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }