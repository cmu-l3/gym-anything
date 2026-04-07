#!/usr/bin/env python3
"""
Verifier for extract_linear_shock_profile task.

Verifies:
1. Presence of the requested CSV.
2. The agent correctly extracted the right area (Pearson correlation to ground truth > 0.90).
3. The agent correctly applied the Gaussian blur (Total Variation check).
4. VLM visual validation of the Plot Profile window UI.
"""

import json
import tempfile
import os
import logging
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_linear_shock_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read exported metrics JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if result.get("error"):
        logger.error(f"Container script error: {result['error']}")

    # ==========================================
    # Criterion 1: CSV File exists (15 points)
    # ==========================================
    if result.get("csv_exists", False):
        score += 15
        feedback_parts.append("Profile CSV exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Profile CSV missing. Task abandoned."}

    # ==========================================
    # Criterion 2: Data Format & Length (15 points)
    # ==========================================
    rows = result.get("csv_rows", 0)
    if 390 <= rows <= 410:
        score += 15
        feedback_parts.append(f"CSV length correct ({rows} rows)")
    elif rows > 0:
        score += 5
        feedback_parts.append(f"CSV length incorrect ({rows} rows, expected 400)")

    # ==========================================
    # Criterion 3: Spatial Accuracy (35 points)
    # ==========================================
    correlation = result.get("correlation_blurred_best", 0.0)
    if correlation > 0.90:
        score += 35
        feedback_parts.append(f"Region accuracy excellent (R={correlation:.3f})")
    elif correlation > 0.70:
        score += 15
        feedback_parts.append(f"Region accuracy partial (R={correlation:.3f})")
    else:
        feedback_parts.append(f"Wrong region extracted (R={correlation:.3f})")

    # ==========================================
    # Criterion 4: Blur Applied (15 points)
    # We measure noise via Total Variation (TV)
    # ==========================================
    tv_agent = result.get("tv_agent", 0.0)
    tv_raw = result.get("tv_gt_raw", 1.0)
    tv_blurred = result.get("tv_gt_blurred", 1.0)
    
    if tv_agent > 0:
        # The blur significantly reduces TV. Check if the agent's TV is closer to the blurred GT
        if tv_agent < (tv_raw * 0.65):
            score += 15
            feedback_parts.append("Gaussian blur detected (smoothed curve)")
        else:
            feedback_parts.append("Gaussian blur not detected (noisy curve)")

    # ==========================================
    # Criterion 5: VLM UI Validation (20 points)
    # ==========================================
    vlm_score = 0
    vlm_feedback = "UI Plot not detected"
    
    # We attempt to check the user-generated screenshot first
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
    
    if result.get("screenshot_exists"):
        temp_img = tempfile.NamedTemporaryFile(suffix='.png', delete=False).name
        try:
            if copy_from_env("/home/ga/AstroImages/measurements/plot_screenshot.png", temp_img):
                img = Image.open(temp_img)
                ans = query_vlm(
                    images=[img],
                    prompt="Does this image clearly show an active 'Plot Profile' graph window (line graph) inside AstroImageJ or ImageJ? Answer strictly 'yes' or 'no'."
                )
                if 'yes' in ans.lower():
                    vlm_score = 20
                    vlm_feedback = "Plot window verified via agent screenshot"
        except Exception as e:
            logger.warning(f"Failed to VLM user screenshot: {e}")
        finally:
            if os.path.exists(temp_img):
                os.unlink(temp_img)

    # Fallback to trajectory frames if user screenshot failed or wasn't provided
    if vlm_score == 0:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            ans = query_vlm(
                images=frames,
                prompt="Review these chronological screenshots. Did the user ever open a 'Plot Profile' graph window showing a 2D line plot? Answer strictly 'yes' or 'no'."
            )
            if 'yes' in ans.lower():
                vlm_score = 20
                vlm_feedback = "Plot window verified via trajectory frames"

    score += vlm_score
    feedback_parts.append(vlm_feedback)

    # Determine final outcome
    key_criteria_met = (result.get("csv_exists") and correlation > 0.85)
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }