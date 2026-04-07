#!/usr/bin/env python3
"""
Verifier for shed_roof_flush_mount task.

Combines programmatic file verification (existence, size, timestamps)
with multi-frame Visual Language Model (VLM) verification to ensure
correct geometry creation and proper Skelion configuration.
"""

import json
import tempfile
import os
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are an expert evaluating a SketchUp 3D modeling task for a solar panel installation.
The agent was instructed to model a shed-roof (mono-pitch) building and place flush-mounted solar panels on the sloped roof in landscape orientation using the Skelion plugin.

Analyze these screenshots (showing workflow progression and final state) and assess the following criteria:

1. shed_roof_geometry: Is there a building with a single-slope (mono-pitch) roof visible? The roof must slope in one continuous direction (e.g., one wall is noticeably higher than the opposite wall). It should NOT be a symmetric gable roof, and it should NOT be a completely flat horizontal roof.
2. panels_present: Are solar panel components (a grid of dark rectangles) visible on the sloped roof surface?
3. flush_mount: Do the panels appear to lie flat along the roof surface (flush-mounted, 0-degree tilt relative to the roof pitch) rather than being tilted up at an additional angle above the roof?
4. 3d_perspective: Does the model appear as a proper 3D volume with visible depth/perspective (not just a 2D top-down flat rectangle)?

Return a JSON object:
{
    "shed_roof_geometry": boolean,
    "panels_present": boolean,
    "flush_mount": boolean,
    "3d_perspective": boolean,
    "reasoning": "Brief explanation of your visual findings"
}
"""

def verify_shed_roof_flush_mount(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_file_size = metadata.get('min_file_size_kb', 50) * 1024

    score = 0
    feedback_parts = []
    details = {}

    # =========================================================================
    # 1. Programmatic Verification (File State & Anti-Gaming)
    # =========================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use C:/ path syntax standard for Python dockur bindings
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    file_created_during_task = result.get('file_created_during_task', False)

    if output_exists:
        score += 10
        feedback_parts.append("File exists")
        
        # Checking size prevents "Empty SketchUp file" gaming
        if output_size > min_file_size:
            score += 10
            feedback_parts.append(f"File size OK (>{min_file_size//1024}KB)")
        else:
            feedback_parts.append(f"File size too small ({output_size} bytes)")

        # Anti-gaming: Ensure file wasn't created before task started
        if file_created_during_task:
            score += 5
            feedback_parts.append("File modified during task execution")
        else:
            feedback_parts.append("File timestamp predates task start (gaming attempt detected)")
    else:
        feedback_parts.append("Target save file not found")

    # =========================================================================
    # 2. VLM Verification (Visual Confirmation of Geometry/Panels)
    # =========================================================================
    parsed_vlm = {}
    
    if query_vlm:
        # Sample trajectory ensures the agent actually did the work
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + ([final] if final else [])

        if images:
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
            parsed_vlm = vlm_result.get('parsed', {})
            details['vlm_reasoning'] = parsed_vlm.get('reasoning', '')

            if parsed_vlm.get('shed_roof_geometry'):
                score += 25
                feedback_parts.append("Shed roof geometry verified")
            else:
                feedback_parts.append("Shed roof geometry NOT detected")

            if parsed_vlm.get('panels_present'):
                score += 25
                feedback_parts.append("Solar panels verified on roof")
            else:
                feedback_parts.append("Solar panels NOT detected")

            if parsed_vlm.get('flush_mount'):
                score += 15
                feedback_parts.append("Panels are flush-mounted")
            else:
                feedback_parts.append("Flush-mount configuration NOT verified")

            if parsed_vlm.get('3d_perspective'):
                score += 10
                feedback_parts.append("Valid 3D perspective")
        else:
            feedback_parts.append("No trajectory images available for VLM")
    else:
        feedback_parts.append("VLM query function not available")

    # =========================================================================
    # 3. Final Evaluation
    # =========================================================================
    # Key criteria must be met to pass at all (file exists, correct geometry, panels exist)
    key_criteria_met = (
        output_exists and 
        file_created_during_task and
        parsed_vlm.get('shed_roof_geometry', False) and 
        parsed_vlm.get('panels_present', False)
    )
    
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }