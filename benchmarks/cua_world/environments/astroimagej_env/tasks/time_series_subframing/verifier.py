#!/usr/bin/env python3
"""
Verifier for Time-Series Subframing task.

Hybrid Verification:
1. Programmatic evaluation of dynamic ground truth:
   - Verifies 20 files were outputted during the task timeframe.
   - Verifies dimensions are exactly 500x500.
   - Evaluates the X/Y centroids of the user's specific subframes.
   - Validates the user's reported measurements against their actual files.
2. VLM evaluation of trajectory frames to ensure the workflow (cropping stack)
   was visually performed in the UI.

Anti-gaming: The true centroid and drift are dynamically calculated from the
actual FITS files the agent saves. Thus, an agent cannot simply write a fake
text report without producing matching valid FITS files.
"""

import os
import json
import tempfile
import logging
import math
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent performing image processing in AstroImageJ.
The task involves loading an image stack, drawing a selection box, cropping the image sequence, and observing centroid coordinates.

Look closely at the screenshots (ordered from earliest to latest) and determine:
1. Did the agent load a stack/sequence of astronomical images?
2. Did the agent draw a rectangular selection box (ROI) on the image?
3. Did the agent execute a Crop command (often creating a smaller 500x500 window)?
4. Is there evidence they used measurement or aperture tools?

Answer in JSON format:
{
    "stack_loaded": true/false,
    "roi_drawn": true/false,
    "crop_executed": true/false,
    "measurements_attempted": true/false,
    "reasoning": "brief explanation"
}
"""

def verify_subframing(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    max_score = 100
    feedback = []

    # 1. Retrieve the task result JSON
    result = {}
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    subframes_count = result.get("subframes_count", 0)
    files_created = result.get("files_created_during_task", False)
    true_dim = result.get("true_dimensions")
    true_c1 = result.get("true_centroid_f1")
    true_drift = result.get("true_drift")
    agent_rep = result.get("agent_reported", {})
    report_exists = result.get("report_exists", False)

    # 2. Check FITS File Export (15 pts)
    if subframes_count == 20 and files_created:
        score += 15
        feedback.append("✅ Exported exactly 20 new FITS subframes")
    elif subframes_count > 0 and files_created:
        score += 7
        feedback.append(f"⚠️ Exported {subframes_count}/20 FITS subframes")
    else:
        feedback.append("❌ Did not export valid FITS subframes during task")

    # 3. Check Dimensions (15 pts)
    if true_dim and true_dim[0] == 500 and true_dim[1] == 500:
        score += 15
        feedback.append("✅ Subframe dimensions exactly 500x500")
    elif true_dim:
        feedback.append(f"❌ Subframe dimensions incorrect: {true_dim[0]}x{true_dim[1]}")

    # 4. Check Report Formatting (10 pts)
    if report_exists and all(k in agent_rep for k in ['star_x_frame1', 'drift_x']):
        score += 10
        feedback.append("✅ Formatted report generated")
    else:
        feedback.append("❌ Report missing or improperly formatted")

    # 5. Check Absolute Centroid Accuracy (20 pts)
    # AstroImageJ and SciPy centroiding algorithms differ slightly, so we allow a generous ±2.5 pixel tolerance
    c1_score = 0
    if true_c1 and 'star_x_frame1' in agent_rep and 'star_y_frame1' in agent_rep:
        dx = abs(agent_rep['star_x_frame1'] - true_c1[0])
        dy = abs(agent_rep['star_y_frame1'] - true_c1[1])
        
        if dx < 2.5 and dy < 2.5:
            c1_score = 20
            feedback.append(f"✅ Centroid coordinate accuracy excellent (Error: {dx:.1f}x, {dy:.1f}y)")
        elif dx < 5.0 and dy < 5.0:
            c1_score = 10
            feedback.append(f"⚠️ Centroid coordinate accuracy marginal (Error: {dx:.1f}x, {dy:.1f}y)")
        else:
            feedback.append(f"❌ Centroid coordinates incorrect (Reported: {agent_rep['star_x_frame1']}, {agent_rep['star_y_frame1']})")
    score += c1_score

    # 6. Check Drift Measurement Accuracy (25 pts)
    # Drift is a differential measurement, meaning systematic offsets between AIJ and SciPy largely cancel out. Tolerance: ±0.8 px
    drift_score = 0
    if true_drift and 'drift_x' in agent_rep and 'drift_y' in agent_rep:
        ddx = abs(agent_rep['drift_x'] - true_drift[0])
        ddy = abs(agent_rep['drift_y'] - true_drift[1])
        
        if ddx < 0.8 and ddy < 0.8:
            drift_score = 25
            feedback.append(f"✅ Drift calculation highly accurate (Error: {ddx:.2f}x, {ddy:.2f}y)")
        elif ddx < 2.0 and ddy < 2.0:
            drift_score = 12
            feedback.append(f"⚠️ Drift calculation approximate (Error: {ddx:.2f}x, {ddy:.2f}y)")
        else:
            feedback.append("❌ Drift calculation incorrect")
    score += drift_score

    # 7. VLM Trajectory Verification (15 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            try:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("stack_loaded") and parsed.get("crop_executed"):
                        vlm_score = 15
                        feedback.append("✅ VLM confirmed visual workflow (Stack cropped)")
                    elif parsed.get("stack_loaded"):
                        vlm_score = 5
                        feedback.append("⚠️ VLM confirmed stack loaded but missed crop")
                    else:
                        feedback.append("❌ VLM did not confirm necessary visual workflow")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")
    score += vlm_score

    passed = score >= 75 and subframes_count > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "true_dimensions": true_dim,
            "true_centroid_f1": true_c1,
            "true_drift": true_drift,
            "agent_reported": agent_rep
        }
    }