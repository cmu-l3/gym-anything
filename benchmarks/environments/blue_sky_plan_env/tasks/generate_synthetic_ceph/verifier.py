#!/usr/bin/env python3
"""
Verifier for generate_synthetic_ceph task.

Verifies:
1. File Creation: Checks if 'lateral_ceph.jpg' was created/modified during task.
2. Image Content (VLM):
   - Projection Mode: Image should look like a thick-slab X-ray (RaySum), not a thin slice.
   - Orientation: True lateral view (superimposed mandible/ear structures).
   - Soft Tissue: Visible profile (nose/lips) alongside bone.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an orthodontic imaging expert verifying a "Synthetic Lateral Cephalogram" generated from a CBCT scan.

Analyze the provided image (which is the output file saved by the agent) and answer the following:

1. **Visualization Mode**: Is this a "Projection" / "Ray Sum" image (looks like a traditional X-ray with superimposition)?
   - *Fail* if it looks like a single noisy thin slice (trabeculation clearly visible, no depth).
   - *Fail* if it looks like a solid white 3D surface rendering.
   - *Pass* if it looks like a thick slab X-ray.

2. **Orientation**: Is the head in a true Lateral position?
   - *Pass* if the left and right sides of the mandible are largely superimposed (or close to it) and the profile is strictly from the side.
   - *Fail* if it is an oblique/diagonal view or a frontal view.

3. **Soft Tissue Visibility**: Can you clearly see the soft tissue profile (forehead, nose tip, lips, chin) against the background?
   - *Pass* if the soft tissue outline is visible.
   - *Fail* if the face is completely black/invisible (bone only).

Provide your response in JSON format:
{
  "is_projection_mode": boolean,
  "is_true_lateral": boolean,
  "soft_tissue_visible": boolean,
  "confidence": "high|medium|low",
  "reasoning": "string"
}
"""

def verify_generate_synthetic_ceph(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_filename = metadata.get('expected_filename', 'lateral_ceph.jpg')

    # 1. Retrieve Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Basic Checks (File existence and timing)
    output_exists = result_data.get('output_exists', False)
    created_during_task = result_data.get('file_created_during_task', False)
    file_size = result_data.get('output_size_bytes', 0)

    score = 0
    feedback = []

    if output_exists:
        score += 10
        feedback.append("Output file exists.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file 'lateral_ceph.jpg' not found."}

    if created_during_task:
        score += 10
        feedback.append("File created during task.")
    else:
        feedback.append("Warning: File timestamp indicates it was not created during this session.")

    if file_size > 50 * 1024: # > 50KB
        score += 10
        feedback.append(f"File size valid ({file_size/1024:.1f} KB).")
    else:
        feedback.append(f"File too small ({file_size} bytes).")

    # 3. Retrieve the Generated Image for VLM Analysis
    # We prioritize checking the actual output file over the screen.
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
    image_path = result_data.get('output_path', "C:\\Users\\Docker\\Documents\\BlueSkyPlan\\lateral_ceph.jpg")
    
    try:
        copy_from_env(image_path, temp_img.name)
        
        # Query VLM with the generated file
        vlm_response = query_vlm(
            prompt=VLM_PROMPT,
            image=temp_img.name
        )
        
        if vlm_response['success']:
            analysis = vlm_response['parsed']
            
            # Criterion: Projection Mode
            if analysis.get('is_projection_mode', False):
                score += 30
                feedback.append("VLM: Valid projection/RaySum mode verified.")
            else:
                feedback.append("VLM Fail: Image appears to be a thin slice or surface render, not a cephalogram.")

            # Criterion: Orientation
            if analysis.get('is_true_lateral', False):
                score += 30
                feedback.append("VLM: True lateral orientation verified.")
            else:
                feedback.append("VLM Fail: Head orientation is not true lateral.")

            # Criterion: Soft Tissue
            if analysis.get('soft_tissue_visible', False):
                score += 10
                feedback.append("VLM: Soft tissue profile is visible.")
            else:
                feedback.append("VLM Warning: Soft tissue profile not clearly visible (check Window/Level).")
        else:
            feedback.append(f"VLM Analysis Error: {vlm_response.get('error')}")

    except Exception as e:
        feedback.append(f"Failed to copy output image for verification: {str(e)}")
        # Fallback: Try VLM on final screenshot if file copy failed
        final_ss = get_final_screenshot(traj)
        if final_ss:
            feedback.append("Falling back to final screenshot analysis...")
            vlm_response = query_vlm(prompt=VLM_PROMPT, image=final_ss)
            # (Simplified logic for fallback - usually implies file save failure, so score capped)
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    # 4. Final Scoring
    # Pass threshold: 70 points.
    # Must have file (10+10+10=30) + Projection(30) + Orientation(30) = 90 max without Soft Tissue
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }