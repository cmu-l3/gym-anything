#!/usr/bin/env python3
"""
Verifier for import_external_3d_model task.

Verification Strategy:
1. Primary (VLM): Analyze final screenshot to detect the 'Bunny' 3D model in the front yard.
2. Secondary (File): Check if the DreamPlan project file (.dpp) was saved/modified.
3. Tertiary (VLM Trajectory): Confirm usage of the 'Import 3D Model' wizard.

Score Distribution:
- Import Wizard Usage (Trajectory): 20 pts
- File Selection (Trajectory): 20 pts
- Object Visible in Scene (VLM): 30 pts
- Correct Placement (Front Yard): 15 pts
- Reasonable Scale (VLM): 15 pts
"""

import json
import logging
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_external_3d_model(traj, env_info, task_info):
    """
    Verify the agent imported bunny.obj and placed it in the yard.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Retrieve result JSON from the container (Windows path mapped to Linux path by framework if needed, 
    # but usually copy_from_env handles the container path).
    # In this env, C:\workspace maps to /workspace.
    
    score = 0
    feedback = []
    
    # 2. File Verification (Project Saved)
    # Check if a project file was actually modified
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        # Map Windows path to Linux mount for copy if needed, or use absolute path known to container
        # We try the standard mount location
        copy_from_env("C:\\workspace\\tasks\\import_external_3d_model\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
            
        if file_result.get("project_saved", False):
            score += 10 # Base points for saving
            feedback.append("Project file saved successfully.")
        else:
            feedback.append("Project file was NOT saved.")
            
    except Exception as e:
        logger.warning(f"Failed to read task result file: {e}")
        feedback.append("Could not verify file system state.")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. VLM Verification (Trajectory & Final State)
    frames = sample_trajectory_frames(traj, n=6)
    final_img = get_final_screenshot(traj)
    
    if not final_img:
         return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    # Combined Prompt for Efficiency
    prompt = """
    You are verifying a task in 'DreamPlan Home Design Software'. 
    The goal is to import a 3D model ('Stanford Bunny') and place it in the front yard.

    Analyze the provided sequence of images (trajectory) and the final image.

    Check for:
    1. **Import Wizard Usage**: Do you see a file picker or 'Import 3D Model' dialog in the trajectory frames?
    2. **Bunny Visibility**: Is a rabbit/bunny sculpture visible in the FINAL image?
    3. **Location**: Is the bunny placed on the grass/outdoors (front yard)?
    4. **Scale**: Is the bunny of a reasonable size (visible, roughly 0.5m-2m tall)? Not a tiny dot, not huge.

    Respond in JSON:
    {
        "wizard_seen": boolean,
        "bunny_visible": boolean,
        "bunny_location_correct": boolean,
        "bunny_scale_ok": boolean,
        "explanation": "string"
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
    
    if vlm_response.get("success"):
        parsed = vlm_response.get("parsed", {})
        
        # Scoring Logic
        if parsed.get("wizard_seen"):
            score += 30
            feedback.append("Import wizard/workflow detected.")
        else:
            feedback.append("Import wizard UI not detected in trajectory.")

        if parsed.get("bunny_visible"):
            score += 30
            feedback.append("Bunny model is visible in the scene.")
            
            if parsed.get("bunny_location_correct"):
                score += 15
                feedback.append("Bunny placed correctly in the yard/outdoors.")
            else:
                feedback.append("Bunny visible but location seems wrong (not in yard).")

            if parsed.get("bunny_scale_ok"):
                score += 15
                feedback.append("Bunny scale is appropriate.")
            else:
                feedback.append("Bunny scale issue (too small or too huge).")
        else:
            feedback.append("Bunny model NOT detected in the final scene.")
            
    else:
        feedback.append("VLM verification failed.")

    # Calculate final status
    passed = score >= 65 and parsed.get("bunny_visible", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }