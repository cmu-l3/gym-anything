#!/usr/bin/env python3
import json
import logging
import math
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gel_mw_analysis(traj, env_info, task_info):
    """
    Verify gel molecular weight analysis task.
    Checks if agent's measured Y-coordinates match the randomized image
    and if the calculated MW is accurate.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check if files exist (30 points)
    if result.get('report_exists'):
        score += 15
        feedback.append("Report JSON found (+15).")
    else:
        feedback.append("Report JSON missing.")
        
    if result.get('plot_exists'):
        score += 15
        feedback.append("Calibration plot found (+15).")
    else:
        feedback.append("Calibration plot missing.")

    if not result.get('report_exists'):
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Data extraction
    agent_data = result.get('agent_report', {})
    gt_data = result.get('ground_truth', {})
    
    # 2. Verify Y-coordinate measurements (Anti-gaming) (40 points)
    # The image was randomized, so hardcoded values will fail here.
    agent_ladder = agent_data.get('standard_bands_y', [])
    gt_ladder = gt_data.get('ladder_y', [])
    
    y_match_score = 0
    if len(agent_ladder) == 5:
        # Check alignment. Allow +/- 5 pixels tolerance
        errors = [abs(a - g) for a, g in zip(agent_ladder, gt_ladder)]
        avg_error = sum(errors) / len(errors)
        
        if avg_error <= 5.0:
            y_match_score = 40
            feedback.append(f"Y-coordinates match ground truth (Avg error: {avg_error:.1f}px) (+40).")
        elif avg_error <= 10.0:
            y_match_score = 20
            feedback.append(f"Y-coordinates acceptable but imprecise (Avg error: {avg_error:.1f}px) (+20).")
        else:
            feedback.append(f"Y-coordinates do not match image (Avg error: {avg_error:.1f}px). Did you measure the randomized image?")
    else:
        feedback.append(f"Expected 5 standard bands, found {len(agent_ladder)}.")

    score += y_match_score

    # 3. Verify Unknown MW Calculation (30 points)
    agent_mw = agent_data.get('calculated_mw_kda', 0)
    gt_mw = gt_data.get('calculated_mw', 0)
    
    if gt_mw > 0:
        # Tolerance: +/- 10%
        error_pct = abs(agent_mw - gt_mw) / gt_mw * 100
        if error_pct <= 10.0:
            score += 30
            feedback.append(f"Calculated MW {agent_mw} is accurate (Error: {error_pct:.1f}%) (+30).")
        elif error_pct <= 20.0:
            score += 15
            feedback.append(f"Calculated MW {agent_mw} is slightly off (Error: {error_pct:.1f}%) (+15).")
        else:
            feedback.append(f"Calculated MW {agent_mw} is incorrect (Expected ~{gt_mw}).")
    else:
        feedback.append("Ground truth MW generation failed.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }