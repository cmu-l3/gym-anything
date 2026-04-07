#!/usr/bin/env python3
"""
Verifier for investment_senior_oas_clawback task.

Margaret Chen — Senior investor with OAS, CPP, RRIF, and complex investment portfolio.
Triggers OAS clawback via high net income. Tests slip aggregation and the 'Return of Capital' trap.

Multi-Criteria Scoring (125 max programmatic points + 25 VLM = 150 -> Normalized to 100):
  Criterion 1: File saved correctly (10 pts)
  Criterion 2: Timestamp valid (5 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4A(OAS) income $8,560 present (10 pts)
  Criterion 5: T4A(P) CPP $14,200 present (10 pts)
  Criterion 6: T4RIF RRIF withdrawal $52,000 present (15 pts) - CRITICAL
  Criterion 7: T3 Trust income data present (10 pts)
  Criterion 8: T5 Interest $2,340 present (5 pts)
  Criterion 9: T5008 Schedule 3 dispositions present (10 pts)
  Criterion 10: Medical ($6,800) and/or Charity ($2,500) present (10 pts)
  Criterion 11: File size guard (5 pts)
  VLM Evaluation: Trajectory verification (25 pts)

Score cap logic enforced to ensure fundamentally broken returns fail.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investment_senior_oas_clawback(traj, env_info, task_info):
    """Verify Margaret Chen senior OAS clawback return."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: No copy_from_env helper available."}

    # 1. Fetch the JSON evaluation results from the container
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:\\Users\\Docker\\Desktop\\senior_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve task results: {e}"}

    # 2. Programmatic Evaluation
    
    # Criterion 1: File saved correctly (10 pts)
    file_ok = result.get('file_exists', False) and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 10
        feedback.append("✅ Return file 'margaret_chen.24t' saved")
    else:
        feedback.append("❌ Return file not found or too small")

    # Criterion 2: Timestamp valid (5 pts)
    if result.get('file_is_new', False):
        score += 5
        feedback.append("✅ File timestamp valid (created during task)")
    else:
        feedback.append("❌ File timestamp invalid")

    # Criterion 3: Taxpayer name (10 pts)
    if result.get('contains_chen', False) and result.get('contains_margaret', False):
        score += 10
        feedback.append("✅ Taxpayer name (Margaret Chen) found")
    else:
        feedback.append("❌ Taxpayer name not found")

    # Criterion 4: T4A(OAS) $8,560 (10 pts)
    if result.get('contains_8560', False):
        score += 10
        feedback.append("✅ T4A(OAS) income $8,560 found")
    else:
        feedback.append("❌ T4A(OAS) income $8,560 not found")

    # Criterion 5: T4A(P) CPP $14,200 (10 pts)
    if result.get('contains_14200', False):
        score += 10
        feedback.append("✅ T4A(P) CPP $14,200 found")
    else:
        feedback.append("❌ T4A(P) CPP $14,200 not found")

    # Criterion 6: T4RIF $52,000 (15 pts) - Crucial for OAS clawback logic
    has_rif = result.get('contains_52000', False)
    if has_rif:
        score += 15
        feedback.append("✅ T4RIF withdrawal $52,000 found")
    else:
        feedback.append("❌ T4RIF withdrawal $52,000 NOT found")

    # Criterion 7: T3 Trust income data (10 pts)
    if result.get('contains_t3_gains', False):
        score += 10
        feedback.append("✅ T3 Trust income values found")
    else:
        feedback.append("❌ T3 Trust income not found")

    # Criterion 8: T5 Interest $2,340 (5 pts)
    if result.get('contains_2340', False):
        score += 5
        feedback.append("✅ T5 Interest $2,340 found")
    else:
        feedback.append("❌ T5 Interest not found")

    # Criterion 9: T5008 Schedule 3 dispositions (10 pts)
    if result.get('contains_t5008_amounts', False):
        score += 10
        feedback.append("✅ T5008 Securities disposition amounts found")
    else:
        feedback.append("❌ T5008 Securities dispositions not found")

    # Criterion 10: Medical / Charity Deductions (10 pts)
    deduction_pts = 0
    if result.get('contains_medical', False):
        deduction_pts += 5
    if result.get('contains_2500', False):
        deduction_pts += 5
    score += deduction_pts
    if deduction_pts > 0:
        feedback.append(f"✅ Deductions found (Medical/Charity) (+{deduction_pts} pts)")
    else:
        feedback.append("❌ Deductions not found")

    # Criterion 11: File size guard (5 pts)
    file_size = result.get('file_size_bytes', 0)
    if file_size > 5000:
        score += 5
        feedback.append("✅ File size adequate for substantive return")

    # 3. VLM Evaluation: Workflow verification (25 pts)
    vlm_points = 0
    query_func = env_info.get('query_vlm')
    if query_func:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_img = get_final_screenshot(traj)
            
            prompt = """You are evaluating a tax agent's performance in StudioTax 2024.
The task involves completing a senior's tax return featuring multiple slips: T4A(OAS), T4A(P), T4RIF, T3, T5, and T5008 capital gains.

Review the progression of screenshots. Did the agent visibly use the software to:
1. Navigate the forms/slips interface (e.g. searching for or opening T-slips)?
2. Enter investment income or capital gains data?
3. Save or attempt to finalize the return?

Return JSON with a single boolean field "workflow_confirmed": true/false."""

            vlm_res = query_func(prompt=prompt, images=frames + [final_img])
            if vlm_res and vlm_res.get("success") and vlm_res.get("parsed", {}).get("workflow_confirmed"):
                vlm_points = 25
                feedback.append("✅ VLM confirmed correct workflow/trajectory (+25 pts)")
            else:
                feedback.append("❌ VLM did not confirm necessary workflow actions")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback.append("⚠️ VLM evaluation failed, 0 points awarded.")

    score += vlm_points

    # 4. Normalize and Cap
    # Total points possible = 125 (Programmatic 100 + VLM 25). 
    # Normalize to 100 scale:
    final_score = int((score / 125) * 100)
    final_score = min(100, final_score)

    # Apply severe caps for missing core components
    if not has_rif:
        final_score = min(final_score, 50)
        feedback.append("⚠️ SCORE CAPPED AT 50: Missing critical T4RIF income ($52,000) driving the OAS clawback scenario.")
        
    has_pension = result.get('contains_14200', False) or result.get('contains_8560', False)
    if not has_pension:
        final_score = min(final_score, 45)
        feedback.append("⚠️ SCORE CAPPED AT 45: Missing both T4A(P) and T4A(OAS) basic senior pensions.")

    passed = final_score >= 60

    return {
        "passed": passed,
        "score": final_score,
        "feedback": "\n".join(feedback)
    }