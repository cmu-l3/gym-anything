#!/usr/bin/env python3
"""
Verifier for Logarithmic Intensity Rescaling Task.
Checks mathematical correctness of the log(1+x)*10000 transform,
dynamic range compression, and report accuracy.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing astronomical image math in AstroImageJ.

The images are sampled chronologically from the agent's trajectory.
Task: The agent must apply a logarithmic stretch to an Eagle Nebula FITS image using the Process > Math menus.

Check for evidence of the following workflow:
1. Is a FITS image (black and white star/nebula field) visible?
2. Did the agent open the "Histogram" or "Measure" windows to get statistics?
3. Did the agent use the Process > Math operations (Add, Log, Multiply)? You might see the math dialog boxes open.
4. Was the image saved (Save As dialog)?

Respond in JSON format:
{
    "fits_visible": true/false,
    "stats_tools_used": true/false,
    "math_operations_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of workflow"
}
"""

def verify_log_scale_eagle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Ground Truth
    gt = {}
    try:
        gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/log_scale_ground_truth.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    if not gt:
        return {"passed": False, "score": 0, "feedback": "Ground truth missing, environment setup may have failed."}

    # 2. Load Agent Result
    result = {}
    try:
        res_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", res_temp.name)
        with open(res_temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(res_temp.name):
            os.unlink(res_temp.name)

    score = 0
    feedback_parts = []
    
    # Check anti-gaming timestamps
    if not result.get('fits_created_during_task', False) or not result.get('report_created_during_task', False):
        feedback_parts.append("WARNING: Output files existed before task started (gaming attempt).")
        # Proceed with checks but this usually fails them or indicates a major issue.

    # Criterion 1: Output FITS exists & valid (20 points)
    if result.get('fits_exists') and result.get('fits_valid'):
        score += 20
        feedback_parts.append("Valid output FITS found")
    else:
        feedback_parts.append("Missing or invalid output FITS")

    # Criterion 2: Pixel values match log(1+x)*10000 (30 points)
    agent_mean = result.get('agent_fits_mean')
    expected_trans_mean = gt.get('trans_mean')
    expected_orig_mean = gt.get('orig_mean')
    
    math_correct = False
    if agent_mean is not None and expected_trans_mean is not None:
        # Check for 'do nothing'
        if abs(agent_mean - expected_orig_mean) < (expected_orig_mean * 0.01):
            feedback_parts.append(f"Image was not transformed (mean matches original {agent_mean:.2f})")
        else:
            # 5% tolerance due to possible floating point differences or missing the +1 offset
            error = abs(agent_mean - expected_trans_mean) / expected_trans_mean
            if error < 0.05:
                score += 30
                math_correct = True
                feedback_parts.append(f"Transform correct (Mean: {agent_mean:.2f})")
            elif error < 0.20:
                score += 15
                feedback_parts.append(f"Transform approximate (Mean: {agent_mean:.2f}, Expected: {expected_trans_mean:.2f})")
            else:
                feedback_parts.append(f"Incorrect transform applied (Mean: {agent_mean:.2f}, Expected: {expected_trans_mean:.2f})")

    # Criterion 3: Dynamic range compressed (10 points)
    agent_max = result.get('agent_fits_max')
    if agent_mean and agent_max and agent_mean > 0:
        agent_dr = agent_max / agent_mean
        orig_dr = gt.get('dr_orig', 0)
        
        # If the dynamic range is less than 50% of the original, it successfully compressed
        if orig_dr > 0 and agent_dr < (orig_dr * 0.5):
            score += 10
            feedback_parts.append(f"Dynamic range successfully compressed (DR: {agent_dr:.2f})")
        else:
            feedback_parts.append(f"Dynamic range not sufficiently compressed (DR: {agent_dr:.2f} vs Orig: {orig_dr:.2f})")

    # Criterion 4 & 5: Report accuracy (35 points)
    report_exists = result.get('report_exists', False)
    reported = result.get('reported_stats', {})
    
    report_correct = False
    if report_exists:
        feedback_parts.append("Report file found")
        subscore = 0
        
        # Check original stats
        if 'ORIGINAL_MEAN' in reported:
            if abs(reported['ORIGINAL_MEAN'] - gt['orig_mean']) / gt['orig_mean'] < 0.05:
                subscore += 10
        
        # Check transformed stats
        if 'TRANSFORMED_MEAN' in reported:
            if abs(reported['TRANSFORMED_MEAN'] - gt['trans_mean']) / gt['trans_mean'] < 0.10:
                subscore += 10
                
        # Check dynamic range
        if 'DYNAMIC_RANGE_TRANSFORMED' in reported:
            dr_val = reported['DYNAMIC_RANGE_TRANSFORMED']
            if isinstance(dr_val, (int, float)) and dr_val > 0:
                subscore += 10
                
        # Method labeling (5 points)
        method = str(reported.get('TRANSFORM_METHOD', '')).lower()
        if 'log1p' in method or 'log(1' in method:
            subscore += 5
            
        score += subscore
        if subscore >= 25:
            report_correct = True
            feedback_parts.append("Reported statistics are accurate")
        else:
            feedback_parts.append(f"Report statistics inaccurate or missing keys (scored {subscore}/35)")
    else:
        feedback_parts.append("Report file NOT found")

    # Criterion 6: VLM Trajectory Check (5 points)
    vlm_passed = False
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("fits_visible") and (parsed.get("stats_tools_used") or parsed.get("math_operations_visible")):
                    score += 5
                    vlm_passed = True
                    feedback_parts.append("VLM verified workflow execution")
                else:
                    feedback_parts.append("VLM did not detect math/stats workflow")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")

    # Final logic
    key_criteria = math_correct and report_correct
    passed = (score >= 60) and key_criteria

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }