#!/usr/bin/env python3
"""
Verifier for design_custom_impression_tray task.

Criteria:
1. File Verification: 'custom_tray_case.bsp' exists and was created during the task.
2. VLM Verification:
   - Tray mesh is visible (distinct from the model).
   - Handle is present on the tray.
   - Tray covers the ridge (valid boundary).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_custom_impression_tray(traj, env_info, task_info):
    """
    Verify the custom impression tray design task.
    """
    # 1. Setup access to environment file
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve result JSON from the Windows environment
    # Note: export_result.ps1 saved to C:\tmp\task_result.json
    # We need to handle the path conversion if necessary, or just use the absolute path
    # accepted by the environment's copy command.
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(r"C:\tmp\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Analyze File Evidence
    score = 0
    feedback_parts = []
    
    output_exists = file_result.get("output_exists", False)
    created_fresh = file_result.get("file_created_during_task", False)
    file_size = file_result.get("output_size_bytes", 0)

    if output_exists and created_fresh:
        score += 20
        feedback_parts.append("✅ Project file saved successfully.")
    elif output_exists:
        score += 5
        feedback_parts.append("⚠️ Project file exists but timestamp is old (reused?).")
    else:
        feedback_parts.append("❌ Project file not saved.")

    if file_size > 10240: # > 10KB implies real data
        score += 5
        feedback_parts.append("✅ File size indicates content.")
    
    # 4. VLM Visual Verification (Critical for 3D tasks)
    # We verify if the agent actually designed the tray
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    images_to_check = frames + [final_screen] if final_screen else frames

    if not images_to_check:
         return {"passed": False, "score": score, "feedback": " ".join(feedback_parts) + " No video evidence found."}

    vlm_prompt = """
    You are evaluating a dental CAD task in Blue Sky Plan. The user is designing a custom impression tray on a 3D jaw model.
    
    Analyze the provided screenshots (chronological order) and the final screen.
    Look for:
    1. A 'Custom Tray' or 'Denture' panel being used.
    2. A line or curve being drawn on the jaw model (Boundary definition).
    3. A new 3D mesh covering the jaw (The Tray), likely a different color than the bone/gums.
    4. A 'Handle' attached to the front of the tray.
    
    Return JSON:
    {
        "tray_tool_used": boolean,
        "boundary_drawn": boolean,
        "tray_mesh_visible": boolean,
        "handle_visible": boolean,
        "spacer_setting_seen": boolean
    }
    """

    try:
        vlm_response = query_vlm(images=images_to_check, prompt=vlm_prompt)
        analysis = vlm_response.get('result', {})
        if isinstance(analysis, str):
            # clean up potential markdown wrapping
            analysis = analysis.replace("