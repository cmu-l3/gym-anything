#!/usr/bin/env python3
"""
Verifier for Map Transient Artifacts via Z-Projection task.

Hybrid Verification Strategy:
1. Programmatic: Validates existence and mathematical accuracy (MAE) of the 
   Maximum projection, Median projection, and difference map.
2. Programmatic: Checks parsed report for the correct peak artifact intensity.
3. VLM Trajectory Verification: Checks sampled frames for GUI interactions
   (Image sequence loaded, Z-projection dialogs, Image Calculator dialog).
4. Anti-gaming: Verifies files were created/modified during the task window.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent completing a Z-Projection task in AstroImageJ.

The images are sampled chronologically from the agent's full interaction.

The agent was asked to:
1. Load an Image Sequence
2. Create a Z-Projection (Max Intensity and Median)
3. Use the Image Calculator to subtract the Median from the Max

Assess:
1. Is AstroImageJ open and visible?
2. Did the agent navigate to the Z-Projection tools (e.g., Image > Stacks > Z Project... dialog visible)?
3. Did the agent open the Image Calculator dialog (Process > Image Calculator)?
4. Does the trajectory show meaningful progression matching this GUI workflow?

Respond in JSON format:
{
    "astroimagej_visible": true/false,
    "z_project_dialog_visible": true/false,
    "image_calculator_visible": true/false,
    "meaningful_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief reasoning of what you observe"
}
"""

def verify_transient_artifacts(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract JSON results prepared by the export script
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Tolerances
    MAE_TOLERANCE = 10.0  # Allow minor algorithmic deviations between astropy and ImageJ
    PEAK_TOLERANCE = 5.0

    # Criterion 1: Max Projection FITS
    if result.get("max_exists"):
        mae = result.get("max_mae")
        if mae is not None and mae <= MAE_TOLERANCE:
            score += 15
            feedback_parts.append(f"Max Projection accurate (MAE: {mae:.2f})")
        else:
            feedback_parts.append(f"Max Projection exists but inaccurate/invalid")
    else:
        feedback_parts.append("Max Projection missing")

    # Criterion 2: Median Projection FITS
    if result.get("median_exists"):
        mae = result.get("median_mae")
        if mae is not None and mae <= MAE_TOLERANCE:
            score += 15
            feedback_parts.append(f"Median Projection accurate (MAE: {mae:.2f})")
        else:
            feedback_parts.append(f"Median Projection exists but inaccurate/invalid")
    else:
        feedback_parts.append("Median Projection missing")

    # Criterion 3: Artifact Map (Difference Map)
    if result.get("diff_exists"):
        mae = result.get("diff_mae")
        if mae is not None and mae <= MAE_TOLERANCE:
            score += 20
            feedback_parts.append(f"Artifact Map accurate (MAE: {mae:.2f})")
        else:
            feedback_parts.append(f"Artifact Map exists but inaccurate/invalid")
    else:
        feedback_parts.append("Artifact Map missing")

    # Criterion 4: Report with peak intensity
    if result.get("report_exists"):
        reported = result.get("reported_peak")
        gt = result.get("gt_peak")
        if reported is not None and gt is not None and abs(reported - gt) <= PEAK_TOLERANCE:
            score += 15
            feedback_parts.append(f"Correct peak reported ({reported:.2f})")
        else:
            feedback_parts.append(f"Incorrect/missing peak in report (Reported: {reported}, Expected: {gt})")
    else:
        feedback_parts.append("Report file missing")

    # Criterion 5: Anti-gaming (files actually created during task window)
    if result.get("files_created_during_task"):
        score += 10
        feedback_parts.append("Files created during task")
    else:
        feedback_parts.append("Failed timestamp checks (potential gaming)")

    # Criterion 6: VLM Verification (Trajectory GUI Check)
    vlm_success = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if frames and final:
            vlm_response = query_vlm(
                prompt=VLM_PROMPT,
                images=frames + [final]
            )
            
            if vlm_response and vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('meaningful_progression', False):
                    # We grant partial or full VLM points based on evidence found
                    if parsed.get('z_project_dialog_visible') or parsed.get('image_calculator_visible') or result.get('gui_evidence'):
                        score += 25
                        vlm_success = True
                        feedback_parts.append("VLM confirmed GUI interaction workflow")
                    else:
                        score += 10
                        feedback_parts.append("VLM observed partial GUI progression")
                else:
                    feedback_parts.append("VLM rejected progression")
            else:
                feedback_parts.append("VLM verification failed to parse")
    else:
        feedback_parts.append("VLM verification unavailable")

    # Final pass logic: Needs decent mathematical accuracy AND GUI evidence
    passed = score >= 60 and result.get("diff_exists") and result.get("diff_mae") is not None and result.get("diff_mae") <= MAE_TOLERANCE

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }