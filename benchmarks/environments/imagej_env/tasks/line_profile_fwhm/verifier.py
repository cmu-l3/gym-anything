#!/usr/bin/env python3
"""
Verifier for line_profile_fwhm task.

Verification Strategy:
1. Programmatic: Check CSV content (row count, FWHM ranges, Peak > Bg).
2. VLM: Verify trajectory shows "Plot" window (evidence of line profiling).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify the line profile workflow
WORKFLOW_PROMPT = """You are verifying an ImageJ task where the user must draw lines on nuclei and plot their intensity profiles.

Analyze the sequence of screenshots.
1. Do you see a window titled "Plot of..." or a graph with a bell-shaped curve (intensity profile)?
2. Do you see straight lines drawn on the image of the cells (yellow/white lines)?
3. Is there a "Fluorescent Cells" or "blue" channel image visible?

Respond in JSON:
{
    "plot_window_visible": true/false,
    "lines_drawn_on_image": true/false,
    "blue_channel_visible": true/false,
    "confidence": "high/medium/low"
}
"""

def verify_line_profile_fwhm(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    query_vlm = env_info.get('query_vlm')

    # Load programmatic result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/line_profile_fwhm_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # Programmatic Checks (75 points total)
    # ------------------------------------------------------------------
    
    # 1. File exists and created during task (15 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 15
        feedback_parts.append("File created correctly")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but timestamp verification failed")
    else:
        feedback_parts.append("Result file not found")

    # 2. Row count >= 5 (20 pts)
    row_count = result.get("row_count", 0)
    if row_count >= 5:
        score += 20
        feedback_parts.append(f"Measured {row_count} nuclei")
    elif row_count > 0:
        score += 10
        feedback_parts.append(f"Measured only {row_count} nuclei (target: 5)")
    else:
        feedback_parts.append("No measurement rows found")

    # 3. FWHM values in plausible range [8, 60] pixels (20 pts)
    valid_fwhm = result.get("valid_fwhm_count", 0)
    total_fwhm = len(result.get("fwhm_values", []))
    
    if total_fwhm > 0:
        if valid_fwhm == total_fwhm and total_fwhm >= 5:
            score += 20
            feedback_parts.append("All FWHM values in valid range")
        elif valid_fwhm >= 3:
            score += 10
            feedback_parts.append(f"{valid_fwhm}/{total_fwhm} FWHM values in valid range")
        else:
            feedback_parts.append("FWHM values appear incorrect (outside 8-60px range)")

    # 4. Peak > Background sanity check (10 pts)
    good_peaks = result.get("peak_gt_bg_count", 0)
    if good_peaks >= 5:
        score += 10
        feedback_parts.append("Intensity values consistent (Peak > BG)")
    
    # 5. Summary stats present (10 pts)
    if result.get("has_summary"):
        score += 10
        feedback_parts.append("Summary statistics included")

    # ------------------------------------------------------------------
    # VLM Verification (25 points total)
    # ------------------------------------------------------------------
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, 5)
        vlm_resp = query_vlm(images=frames, prompt=WORKFLOW_PROMPT)
        
        if vlm_resp and vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('plot_window_visible'):
                vlm_score += 15
                feedback_parts.append("VLM: Plot window detected")
            
            if parsed.get('lines_drawn_on_image'):
                vlm_score += 10
                feedback_parts.append("VLM: Measurement lines detected")
            
            score += vlm_score
    else:
        # Graceful fallback if VLM unavailable, scale remaining points
        if score >= 60:
            score = min(100, int(score * (100/75)))
            feedback_parts.append("(VLM skipped, score scaled)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }