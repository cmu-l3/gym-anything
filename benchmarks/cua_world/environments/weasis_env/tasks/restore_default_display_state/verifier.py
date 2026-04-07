#!/usr/bin/env python3
"""
Verifier for Restore Default Display State task.

This verifier employs a multi-signal approach:
1. File validation (existence, timestamps, sizes)
2. Programmatic structural similarity (Root Mean Square difference via PIL)
3. VLM Trajectory analysis to ensure genuine UI interactions.
"""

import os
import json
import math
import logging
import tempfile
from PIL import Image, ImageChops

# Attempt to import VLM helpers from the gym_anything framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def rmsdiff(im1, im2):
    """Calculate the root-mean-square difference between two PIL images."""
    # Convert to grayscale to simplify luminance/contrast difference checking
    im1 = im1.convert('L')
    im2 = im2.convert('L')
    
    # Resize im2 to im1 to avoid dimension mismatch errors (e.g., if Weasis viewport slightly shifted)
    if im1.size != im2.size:
        im2 = im2.resize(im1.size)
        
    diff = ImageChops.difference(im1, im2)
    h = diff.histogram()
    sq = (value * ((idx % 256) ** 2) for idx, value in enumerate(h))
    sum_of_squares = sum(sq)
    return math.sqrt(sum_of_squares / float(im1.size[0] * im1.size[1]))

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent interacting with a DICOM Viewer (Weasis).

The agent's task was to:
1. Export a baseline image via the UI
2. Apply visual transformations (zoom, invert, rotate)
3. Export the altered image via the UI
4. Use the application's built-in "Reset" functionality (via toolbar buttons, right click context menu, or menus) to restore the original view.
5. Export the restored image via the UI

Based on these chronologically sampled frames, assess:
1. UI_USED_FOR_TRANSFORMS: Do you see evidence of the agent interacting with the Weasis graphical UI (menus, context menus, toolbar icons) to alter the image or open the Export dialog?
2. UI_USED_FOR_RESET: Do you see evidence of the agent clicking a 'Reset' button, using a right-click 'Reset' menu option, or similar UI feature to revert the image?
3. TERMINAL_CHEATING: Did the agent spend its time entirely in the terminal manually copying/converting files instead of using the Weasis UI?

Respond in JSON format:
{
    "ui_used_for_transforms": true/false,
    "ui_used_for_reset": true/false,
    "terminal_cheating": true/false,
    "reasoning": "brief explanation of what interactions were observed"
}
"""

def verify_restore_default_display_state(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    rms_restored_threshold = metadata.get('rms_restored_threshold', 10.0)
    rms_altered_threshold = metadata.get('rms_altered_threshold', 40.0)

    # 1. Fetch JSON results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    f1 = result.get('file_1', {})
    f2 = result.get('file_2', {})
    f3 = result.get('file_3', {})

    # Criterion 1: Files Exist and were created during task (15 points + 15 points)
    all_exist = f1.get('exists') and f2.get('exists') and f3.get('exists')
    all_valid_time = f1.get('valid_time') and f2.get('valid_time') and f3.get('valid_time')
    all_valid_size = (f1.get('size', 0) > 1000) and (f2.get('size', 0) > 1000) and (f3.get('size', 0) > 1000)

    if all_exist and all_valid_size:
        score += 15
        feedback_parts.append("All exported files exist with valid sizes")
    else:
        feedback_parts.append("Missing or empty export files")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    if all_valid_time:
        score += 15
        feedback_parts.append("Files created during task session")
    else:
        feedback_parts.append("Files existed before task (possible cheating)")

    # 2. Programmatic Image Analysis (RMS)
    f1_local = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    f2_local = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    f3_local = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    
    img1, img2, img3 = None, None, None
    try:
        copy_from_env(f1.get('path'), f1_local.name)
        copy_from_env(f2.get('path'), f2_local.name)
        copy_from_env(f3.get('path'), f3_local.name)
        
        img1 = Image.open(f1_local.name)
        img2 = Image.open(f2_local.name)
        img3 = Image.open(f3_local.name)
        
        rms_1_2 = rmsdiff(img1, img2)
        rms_1_3 = rmsdiff(img1, img3)
        
        # Criterion 2: Altered image is significantly different (25 points)
        if rms_1_2 > rms_altered_threshold:
            score += 25
            feedback_parts.append(f"Altered view verified (RMS: {rms_1_2:.1f})")
        else:
            feedback_parts.append(f"Altered view not distinct enough (RMS: {rms_1_2:.1f})")

        # Criterion 3: Restored image matches original (25 points)
        if rms_1_3 < rms_restored_threshold:
            score += 25
            feedback_parts.append(f"Restored view verified (RMS: {rms_1_3:.1f})")
        else:
            feedback_parts.append(f"Restored view differs from original (RMS: {rms_1_3:.1f})")
            
    except Exception as e:
        logger.error(f"Image analysis failed: {e}")
        feedback_parts.append("Failed to analyze image structural similarity")
    finally:
        for f in [img1, img2, img3]:
            if f:
                f.close()
        for f_path in [f1_local.name, f2_local.name, f3_local.name]:
            if os.path.exists(f_path):
                os.unlink(f_path)

    # 3. VLM Trajectory Verification (20 points)
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            vlm_res = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                ui_used = parsed.get("ui_used_for_transforms", False) or parsed.get("ui_used_for_reset", False)
                terminal_cheat = parsed.get("terminal_cheating", False)
                
                if ui_used and not terminal_cheat:
                    score += 20
                    feedback_parts.append("VLM confirmed UI usage for workflow")
                else:
                    feedback_parts.append("VLM observed potential terminal cheating or lack of UI usage")
            else:
                score += 10  # Partial credit if VLM fails gracefully but files look correct
                feedback_parts.append("VLM query failed, partial credit awarded")
        except Exception as e:
            logger.error(f"VLM verification exception: {e}")
            score += 10
            feedback_parts.append("VLM verification errored")
    else:
        # If VLM is totally unavailable in the runner, grant the points assuming file checks passed
        score += 20
        feedback_parts.append("VLM unavailable, auto-awarding interaction points")

    passed = score >= 80 and (rms_1_3 < rms_restored_threshold if img3 else False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }