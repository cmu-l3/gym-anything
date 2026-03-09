#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_image_registration_alignment(traj, env_info, task_info):
    """
    Verify image registration task using results calculated in container.
    """
    # 1. Retrieve result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Unpack data
    reg_exists = result.get("registered_exists", False)
    diff_exists = result.get("difference_exists", False)
    report_exists = result.get("report_exists", False)
    ncc_final = result.get("ncc_final", 0.0)
    ncc_base = result.get("ncc_baseline", 0.0)
    is_copy = result.get("is_copy", False)
    
    gt = result.get("ground_truth", {})
    gt_tx = gt.get("translation_x", 0)
    gt_ty = gt.get("translation_y", 0)
    gt_rot = gt.get("rotation_deg", 0)
    
    # 2. Scoring Criteria
    
    # File Existence
    if reg_exists:
        score += 10
        feedback.append("Registered image found (+10)")
    else:
        feedback.append("Registered image missing")

    if diff_exists:
        score += 8
        feedback.append("Difference image found (+8)")
    
    if report_exists:
        score += 10
        feedback.append("Report found (+10)")

    # Image Quality (NCC)
    if not is_copy and reg_exists:
        if ncc_final >= 0.70:
            score += 12
            feedback.append(f"Fair alignment (NCC={ncc_final:.2f}) (+12)")
            
            if ncc_final >= 0.85:
                score += 10
                feedback.append(f"Good alignment (NCC >= 0.85) (+10)")
        
        improvement = ncc_final - ncc_base
        if improvement > 0.05:
            score += 10
            feedback.append(f"Alignment improved NCC by {improvement:.2f} (+10)")
        else:
            feedback.append(f"No significant improvement (delta={improvement:.2f})")
    
    elif is_copy:
        feedback.append("Result appears to be a copy of input (Anti-gaming penalty)")

    # Parameter Accuracy
    # Note: Agent might report the transformation applied TO the image (inverse) or the motion
    # We allow tolerance and sign flip check
    rep_tx = result.get("reported_tx")
    rep_ty = result.get("reported_ty")
    rep_rot = result.get("reported_rot")
    
    # Function to check with tolerance and sign flexibility
    def check_param(val, target, name, tol, points):
        if val is None: return 0, f"{name} not reported"
        diff = abs(val - target)
        diff_inv = abs(val + target) # Check for sign flip
        if diff <= tol:
            return points, f"{name} accurate ({val}) (+{points})"
        elif diff_inv <= tol:
            return points, f"{name} accurate (sign flipped) ({val}) (+{points})"
        return 0, f"{name} inaccurate (got {val}, expected +/-{target})"

    s_tx, f_tx = check_param(rep_tx, gt_tx, "Tx", 5.0, 8)
    s_ty, f_ty = check_param(rep_ty, gt_ty, "Ty", 5.0, 8)
    s_rot, f_rot = check_param(rep_rot, gt_rot, "Rot", 1.5, 7)
    
    score += s_tx + s_ty + s_rot
    feedback.append(f_tx)
    feedback.append(f_ty)
    feedback.append(f_rot)

    # 3. VLM Verification (Trajectory)
    # Since we can't run VLM here directly, we assume framework handles it,
    # or we implement a simple placeholder if VLM is optional.
    # For this template, we'll award VLM points if the task seems honestly attempted (files exist + improvement)
    vlm_score = 0
    if reg_exists and (ncc_final - ncc_base > 0.01):
        vlm_score = 7
        feedback.append("Workflow verification assumed passed (+7)")
    score += vlm_score

    return {
        "passed": score >= 55,
        "score": score,
        "feedback": "; ".join(feedback)
    }