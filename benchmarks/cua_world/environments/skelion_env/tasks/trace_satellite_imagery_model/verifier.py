#!/usr/bin/env python3
"""
Verifier for trace_satellite_imagery_model task.

VERIFICATION METRICS:
1. Output File Integrity (File exists, created during task, valid file size > 50KB)
2. Trajectory VLM Check 1: Was an aerial image imported into the SketchUp scene?
3. Trajectory VLM Check 2: Was a 3D building modeled/extruded on top of the image?
4. Trajectory VLM Check 3: Were Skelion solar panels placed on the roof?

Multiple independent signals ensure the agent cannot spoof the final state.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


VERIFICATION_PROMPT = """You are verifying if an AI agent successfully completed a solar design pipeline in SketchUp.

TASK GOALS:
1. Import an aerial image (satellite photo) onto the ground plane.
2. Trace a building footprint and extrude it into 3D (approx 4m high).
3. Place a solar panel array on the roof using the Skelion plugin.

Carefully examine this sequence of screenshots (taken during the task workflow) and the final screenshot. 
Evaluate the presence of the following three elements:

1. Image Imported: Can you see an aerial photo/satellite image placed on the ground in the SketchUp workspace?
2. Building Modeled: Is there a 3D building geometry (extruded blocks/walls) clearly constructed over or near the aerial image?
3. Panels Placed: Are there solar panels (blue/dark grids or rectangles) placed on top of the 3D building?

Respond strictly in JSON format:
{
    "image_imported": true/false,
    "building_modeled": true/false,
    "panels_placed": true/false,
    "reasoning": "Briefly explain the visual evidence for your conclusions."
}
"""

def verify_trace_satellite_imagery_model(traj, env_info, task_info):
    """
    Verifies that the agent properly imported an image, scaled/modeled a building, 
    and added solar panels.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available from environment."}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Evaluate Output File Metrics
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: using standard Windows path for copy inside the container
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # File Existing Check (15 pts)
    if result.get('output_exists', False):
        score += 15
        feedback_parts.append("✅ SketchUp model file exists.")
    else:
        feedback_parts.append("❌ Target .skp file was not created.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # File Timestamps Check - Anti-gaming (15 pts)
    if result.get('file_created_during_task', False):
        score += 15
        feedback_parts.append("✅ File created/modified during task execution.")
    else:
        feedback_parts.append("❌ File existed prior to task or timestamps invalid.")

    # File Size Check - Ensure it's not an empty file (10 pts)
    # A blank SketchUp file is ~25KB. With an imported image + panels, it should easily clear 50KB.
    size_kb = result.get('output_size_bytes', 0) / 1024
    if size_kb >= 50:
        score += 10
        feedback_parts.append(f"✅ File size reasonable ({size_kb:.1f} KB).")
    else:
        feedback_parts.append(f"❌ File size suspiciously small ({size_kb:.1f} KB).")

    # 2. VLM Trajectory Verification
    if not query_vlm:
        feedback_parts.append("⚠️ VLM evaluation not available, relying strictly on file metrics.")
        return {
            "passed": score >= 40,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    logger.info("Sampling trajectory frames for VLM verification...")
    # Sample 4 frames along the workflow plus the final screenshot
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        feedback_parts.append("❌ No trajectory images available for VLM verification.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    vlm_result = query_vlm(
        prompt=VERIFICATION_PROMPT,
        images=frames
    )

    if not vlm_result.get("success"):
        feedback_parts.append(f"❌ VLM query failed: {vlm_result.get('error')}")
    else:
        parsed = vlm_result.get("parsed", {})
        
        # Image Imported (20 pts)
        if parsed.get("image_imported", False):
            score += 20
            feedback_parts.append("✅ VLM confirmed aerial image import.")
        else:
            feedback_parts.append("❌ VLM did not detect imported image.")

        # Building Modeled (20 pts)
        if parsed.get("building_modeled", False):
            score += 20
            feedback_parts.append("✅ VLM confirmed 3D building modeling.")
        else:
            feedback_parts.append("❌ VLM did not detect 3D building trace/extrusion.")

        # Panels Placed (20 pts)
        if parsed.get("panels_placed", False):
            score += 20
            feedback_parts.append("✅ VLM confirmed solar panel placement.")
        else:
            feedback_parts.append("❌ VLM did not detect solar panels on the roof.")

        if "reasoning" in parsed:
            feedback_parts.append(f"VLM Note: {parsed['reasoning']}")

    # Pass criteria: Score must be at least 70 (meaning the file was created during the task + at least 2 VLM steps verified)
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }