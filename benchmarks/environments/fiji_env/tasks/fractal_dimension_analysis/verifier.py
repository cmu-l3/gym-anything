#!/usr/bin/env python3
"""
Verifier for fractal_dimension_analysis task.

Criteria:
1. Result CSV exists and created during task (30 pts)
2. Plot PNG exists and created during task (20 pts)
3. Fractal Dimension (D) is valid (1.0 < D < 1.5) (40 pts)
   - This validates the workflow steps (Threshold -> Outline -> Box Count).
   - Filled shapes would give D=2.0. Noisy input would give higher D.
4. VLM Verification of workflow (10 pts)
   - Checks if 'Fractal Box Count' window or plot was visible.

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fractal_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result
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

    # 2. Check CSV (30 pts)
    csv_ok = result.get("csv_exists", False) and result.get("csv_created_during_task", False)
    if csv_ok:
        score += 30
        feedback.append("Result CSV created.")
    else:
        feedback.append("Result CSV missing or not created during task.")

    # 3. Check Plot (20 pts)
    plot_ok = result.get("plot_exists", False) and result.get("plot_created_during_task", False)
    if plot_ok:
        score += 20
        feedback.append("Plot image created.")
    else:
        feedback.append("Plot image missing.")

    # 4. Validate D Value (40 pts)
    # The 'blobs.gif' sample, when outlined, typically has D between 1.05 and 1.30 depending on thresholding.
    # Filled blobs would correspond to D=2 (topological dimension of surface).
    # Single pixel outlines are 1 < D < 2.
    d_val = result.get("parsed_d_value", 0.0)
    d_valid = False
    
    if 1.0 < d_val < 1.5:
        score += 40
        d_valid = True
        feedback.append(f"Fractal Dimension D={d_val:.4f} is within valid range (1.0-1.5).")
    elif 1.9 < d_val < 2.1:
        feedback.append(f"Fractal Dimension D={d_val:.4f} indicates filled shapes, not outlines. Did you forget 'Process > Binary > Outline'?")
    else:
        feedback.append(f"Fractal Dimension D={d_val:.4f} is out of expected range.")

    # 5. VLM Verification (10 pts)
    # Check trajectory for the "Fractal Box Count" plot or dialog
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    vlm_prompt = """
    Check these screenshots of a Fiji (ImageJ) session.
    The user should have:
    1. Opened an image of blobs.
    2. Converted it to binary outlines (white background, black outlines or vice versa).
    3. Run 'Fractal Box Count', which produces a Plot Window (Log-Log graph).
    
    Answer JSON:
    {
        "outlines_visible": boolean, 
        "plot_window_visible": boolean,
        "reason": "..."
    }
    """
    
    vlm_score = 0
    try:
        # Use last few frames + final for best context
        check_images = frames[-2:] + [final] if len(frames) >= 2 else [final]
        vlm_res = query_vlm(images=check_images, prompt=vlm_prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("plot_window_visible"):
                vlm_score += 10
                feedback.append("VLM confirmed plot window visibility.")
            elif parsed.get("outlines_visible"):
                vlm_score += 5
                feedback.append("VLM confirmed outlines, but plot window not clearly seen.")
            else:
                feedback.append("VLM could not confirm workflow visual steps.")
    except Exception as e:
        feedback.append(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final decision
    # Must have valid D value to pass (shows correct algorithm use)
    passed = (score >= 70) and d_valid

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "d_value": d_val,
            "csv_ok": csv_ok,
            "plot_ok": plot_ok,
            "vlm_score": vlm_score
        }
    }