#!/usr/bin/env python3
"""
Verifier for brain_window_slice_export task.

Scoring (100 points total):
1. PNG Image Export (45 pts):
   - File exists and is valid PNG: 15 pts
   - Created during task: 10 pts
   - Pixel analysis indicates brain window (not bone/default): 20 pts
2. Slice Info (25 pts):
   - File exists and contains integer: 10 pts
   - Integer in valid range (40-80 for ventricles): 15 pts
3. VLM Verification (30 pts):
   - Visual confirmation of axial view, brain tissue contrast, and visible ventricles.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_brain_window_slice_export(traj, env_info, task_info):
    """Verify brain window settings and ventricle visibility."""
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    min_slice = metadata.get('min_slice_index', 40)
    max_slice = metadata.get('max_slice_index', 80)
    min_gray_ratio = metadata.get('brain_window_min_gray_percent', 20.0) / 100.0

    score = 0
    feedback_parts = []
    
    # Load JSON result from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # --- Criterion 1: Image Existence & Validity (25 pts) ---
    if result.get("image_exists") and result.get("is_png"):
        score += 15
        feedback_parts.append("Valid PNG exported")
        if result.get("image_created_during_task"):
            score += 10
            feedback_parts.append("New file created")
        else:
            feedback_parts.append("File timestamp pre-dates task start")
    else:
        feedback_parts.append("PNG output missing or invalid")

    # --- Criterion 2: Brain Window Detection (20 pts) ---
    # We check if the image has a significant amount of mid-gray pixels.
    # Bone window images are mostly black/white.
    gray_ratio = result.get("gray_pixel_ratio", 0.0)
    if gray_ratio >= min_gray_ratio:
        score += 20
        feedback_parts.append(f"Brain window detected (gray ratio: {gray_ratio:.2f})")
    else:
        feedback_parts.append(f"Image contrast incorrect (gray ratio: {gray_ratio:.2f} < {min_gray_ratio}). Looks like Bone or Default window.")

    # --- Criterion 3: Slice Info (25 pts) ---
    slice_num = result.get("slice_number")
    if result.get("info_exists") and slice_num is not None:
        score += 10
        if min_slice <= slice_num <= max_slice:
            score += 15
            feedback_parts.append(f"Slice {slice_num} in correct ventricle range")
        else:
            feedback_parts.append(f"Slice {slice_num} outside expected ventricle range ({min_slice}-{max_slice})")
    else:
        feedback_parts.append("Slice info text file missing or unreadable")

    # --- Criterion 4: VLM Visual Verification (30 pts) ---
    # We check the actual exported image if possible, otherwise the final screenshot
    image_to_check = get_final_screenshot(traj)
    
    # If the agent exported the image, we'd ideally check that specific image.
    # Since we can't easily drag the exported file into the VLM context without copying it,
    # we rely on the final screenshot which usually shows the result or the app state.
    # Ideally, the agent left the app in the state of the export.
    
    if image_to_check:
        prompt = """
        Analyze this screenshot of the InVesalius 3 medical software.
        1. Is an Axial CT slice visible (top-left usually, or main view)?
        2. Does the image contrast look like a "Brain Window" (soft gray brain tissue visible) or a "Bone Window" (mostly black/white)?
        3. Can you see the lateral ventricles (dark butterfly/X-shaped structures in the middle of the brain)?
        
        Answer with JSON:
        {
            "axial_view_visible": true/false,
            "contrast_type": "brain" or "bone" or "other",
            "ventricles_visible": true/false
        }
        """
        vlm_res = query_vlm(prompt, image=image_to_check)
        
        if vlm_res['success']:
            parsed = vlm_res.get('parsed', {})
            if parsed.get('axial_view_visible'):
                score += 5
            
            if parsed.get('contrast_type') == 'brain' or parsed.get('ventricles_visible'):
                score += 25
                feedback_parts.append("VLM confirmed brain anatomy/ventricles visible")
            else:
                feedback_parts.append("VLM did not clearly see brain window/ventricles")
        else:
            # Fallback if VLM fails: give points if histogram check passed strongly
            if gray_ratio > (min_gray_ratio * 1.5):
                score += 20
                feedback_parts.append("VLM failed, trusting histogram")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }