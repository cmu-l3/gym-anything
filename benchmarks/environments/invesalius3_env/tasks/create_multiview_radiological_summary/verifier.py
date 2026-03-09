#!/usr/bin/env python3
"""
Verifier for create_multiview_radiological_summary task.

Verification Strategy:
1. Programmatic: Check if /home/ga/Documents/radiology_summary.png exists and was created during the task.
2. VLM: Analyze the generated image to verify:
   - 4-panel layout (Axial, Sagittal, Coronal, 3D)
   - 3D background is WHITE
   - 2D slices show anatomy (skull structures), not empty space
"""

import json
import os
import tempfile
import logging
import sys
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt for image analysis
VERIFICATION_PROMPT = """
You are a radiologist's assistant verifying a software task. 
Analyze this screenshot of the InVesalius medical software.

I need to check three specific requirements:

1. **Layout**: Is the screen showing a 4-panel view (three 2D slice views and one 3D reconstruction view)?
2. **3D Background**: Look at the 3D visualization panel (usually bottom-right or top-right, showing the skull). Is the background color WHITE (or very light grey)? It should NOT be black, blue, or a gradient.
3. **Anatomy Navigation**: Look at the 2D slice views (Axial, Sagittal, Coronal). Do they show cross-sections of the skull/brain? (i.e., not blank/empty black space, and not just the very tip of the head).

Respond in JSON format:
{
  "is_4_panel_layout": true/false,
  "is_3d_background_white": true/false,
  "is_anatomy_visible_in_slices": true/false,
  "confidence": "high/medium/low",
  "reasoning": "brief explanation"
}
"""

def verify_radiological_summary(traj, env_info, task_info):
    """Verify the radiological summary task."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Load programmatic result
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

    # Criterion 1: File exists and is a valid size (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        file_size = result.get("file_size_bytes", 0)
        if file_size > 50000: # >50KB
            score += 20
            feedback_parts.append("Summary image file created successfully")
        else:
            feedback_parts.append("File created but too small (likely empty/corrupt)")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("No new output file found at /home/ga/Documents/radiology_summary.png")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. VLM Verification of the Content
    # We need to analyze the ACTUAL OUTPUT FILE, not just the final screen state (though they might be the same).
    # We will copy the output image from the environment to host for VLM analysis.
    
    try:
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp_img.close()
        copy_from_env(result["output_path"], tmp_img.name)
        
        # Query VLM
        vlm_response = query_vlm(
            prompt=VERIFICATION_PROMPT,
            image=tmp_img.name
        )
        os.unlink(tmp_img.name)
        
        if not vlm_response.get("success"):
            feedback_parts.append(f"VLM analysis failed: {vlm_response.get('error')}")
        else:
            parsed = vlm_response.get("parsed", {})
            
            # Criterion 2: 4-Panel Layout (30 pts)
            if parsed.get("is_4_panel_layout"):
                score += 30
                feedback_parts.append("Correct 4-panel layout confirmed")
            else:
                feedback_parts.append("Layout incorrect (expected 4-panel)")

            # Criterion 3: White Background (30 pts)
            if parsed.get("is_3d_background_white"):
                score += 30
                feedback_parts.append("3D background is white")
            else:
                feedback_parts.append("3D background color incorrect (expected white)")

            # Criterion 4: Anatomy Visible (20 pts)
            if parsed.get("is_anatomy_visible_in_slices"):
                score += 20
                feedback_parts.append("Anatomy visible in slice views")
            else:
                feedback_parts.append("Slice views appear empty (navigation required)")
                
    except Exception as e:
        feedback_parts.append(f"Error during VLM verification: {e}")

    # Pass logic: Need >= 70 points
    # This implies file exists (20) + at least two visual criteria met (approx 50+)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }