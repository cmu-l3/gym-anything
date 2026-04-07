#!/usr/bin/env python3
"""
Verifier for Atmospheric Extinction Task in AstroImageJ.
"""

import json
import os
import re
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for checking visual trajectory evidence
TRAJECTORY_PROMPT = """You are verifying an astronomy task in AstroImageJ.
The user was asked to open an image sequence, place apertures on a star, and extract photometry.

Look at these chronologically sampled screenshots from the session. Check for the following evidence:
1. APP_USED: Is AstroImageJ open and visible?
2. IMAGES_LOADED: Is there a grayscale astronomical image (star field) visible?
3. APERTURES_PLACED: Are there green, yellow, or red circular aperture marks placed on the stars?
4. MEASUREMENTS_VISIBLE: Is there a "Measurements" or "Results" table window showing numeric data?

Respond in pure JSON format:
{
    "app_used": true/false,
    "images_loaded": true/false,
    "apertures_placed": true/false,
    "measurements_visible": true/false,
    "observations": "brief summary of what you see"
}
"""

def verify_extinction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Read exported task results
    result = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Read Ground Truth
    gt = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/extinction_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Validate output files exist
    if result.get("data_exists"):
        score += 15
        feedback_parts.append("✅ Photometry data exported")
    else:
        feedback_parts.append("❌ Photometry data file not found")

    if result.get("report_exists"):
        score += 15
        feedback_parts.append("✅ Report file created")
    else:
        feedback_parts.append("❌ Report file not found")

    # Verify Computed Slope
    reported_coef = None
    if result.get("report_exists"):
        content = result.get("report_content", "")
        # Look for EXTINCTION_COEFFICIENT: 0.XX
        match = re.search(r'EXTINCTION_COEFFICIENT:\s*([0-9\.\-]+)', content)
        if match:
            try:
                reported_coef = float(match.group(1))
            except ValueError:
                pass

    expected_coef = gt.get("extinction_coefficient", 0.15)
    tolerance = task_info.get("metadata", {}).get("tolerance", 0.05)
    
    if reported_coef is not None:
        diff = abs(reported_coef - expected_coef)
        if diff <= tolerance:
            score += 50
            feedback_parts.append(f"✅ Extinction coefficient accurate ({reported_coef:.3f})")
        elif diff <= tolerance * 2:
            score += 25
            feedback_parts.append(f"⚠️ Extinction coefficient slightly inaccurate ({reported_coef:.3f} vs expected {expected_coef:.3f})")
        else:
            feedback_parts.append(f"❌ Extinction coefficient inaccurate ({reported_coef:.3f} vs expected {expected_coef:.3f})")
    else:
        feedback_parts.append("❌ Could not parse EXTINCTION_COEFFICIENT from report")

    # 3. VLM Verification (Trajectory Analysis)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("images_loaded"): vlm_score += 5
                if parsed.get("apertures_placed"): vlm_score += 10
                if parsed.get("measurements_visible"): vlm_score += 5
                
                score += vlm_score
                
                if vlm_score == 20:
                    feedback_parts.append("✅ VLM confirmed AstroImageJ interaction workflow")
                elif vlm_score > 0:
                    feedback_parts.append("⚠️ VLM confirmed partial AstroImageJ interaction")
                else:
                    feedback_parts.append("❌ VLM found no visual evidence of AstroImageJ usage")
            else:
                feedback_parts.append("⚠️ VLM verification failed")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }