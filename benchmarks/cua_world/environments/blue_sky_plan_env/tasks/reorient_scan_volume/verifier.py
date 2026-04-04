#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorient_scan_volume(traj, env_info, task_info):
    """
    Verifies the reorient_scan_volume task for Blue Sky Plan.
    
    Criteria:
    1. Output screenshot exists and was created during task (anti-gaming).
    2. Project file was saved.
    3. VLM Verification of Trajectory:
       - Did the agent access orientation tools?
       - Did the views change from the initial tilted state?
    4. VLM Verification of Final Output:
       - Does the saved screenshot show aligned MPR views?
    """
    
    # 1. Setup and retrieve data from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # We expect the result JSON at C:\workspace\task_result.json
    # The container path format depends on the env driver, but usually for Windows containers 
    # accessed via standard docker cp, the path is absolute in the container.
    # Note: If copy_from_env takes a posix-style path for windows container, 
    # it might need adjustment, but usually standard paths work.
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # Fetch result JSON
        copy_from_env("C:\\workspace\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            
        # Try to fetch the user's output screenshot for VLM analysis
        # The JSON contains the path: C:\Users\Docker\Documents\ReorientedScan\reorientation_result.png
        user_screenshot_path = result_data.get("screenshot_path")
        user_screenshot_available = False
        if user_screenshot_path and result_data.get("screenshot_exists"):
            try:
                copy_from_env(user_screenshot_path, temp_screenshot.name)
                user_screenshot_available = True
            except Exception as e:
                logger.warning(f"Could not copy user screenshot: {e}")

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    # Criterion A: Technical Evidence (40 points)
    if result_data.get("screenshot_exists") and result_data.get("screenshot_created_during_task"):
        score += 20
        feedback_parts.append("✅ Screenshot created")
    else:
        feedback_parts.append("❌ No valid screenshot created")
        
    if result_data.get("project_exists") and result_data.get("project_saved_during_task"):
        score += 15
        feedback_parts.append("✅ Project saved")
    else:
        feedback_parts.append("❌ Project not saved")
        
    if result_data.get("app_was_running"):
        score += 5
    
    # Criterion B: VLM Trajectory Verification (30 points)
    # Check if agent actually performed work
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback_parts.append("⚠️ No trajectory frames available")
    else:
        traj_prompt = """
        Analyze these screenshots of a user using Blue Sky Plan dental software.
        The user should be reorienting/rotating a 3D volume to fix head tilt.
        
        Look for:
        1. Opening of 'Module' menus or 'Orientation'/'MPR' panels.
        2. Mouse cursors dragging on the 2D slice views (Axial, Sagittal, Coronal) to rotate lines.
        3. Visual changes in the alignment of the skull/teeth between frames.
        
        Did the user perform these actions?
        """
        
        traj_result = query_vlm(images=frames, prompt=traj_prompt)
        if traj_result.get("success"):
            # A simple heuristic: if VLM is positive, give points
            # We assume the VLM returns text, we parse for positive sentiment or specific keywords
            # For this template, we'll assume manual review of VLM output or a structured prompt
            # Let's try a structured boolean prompt
            bool_check = query_vlm(
                images=frames, 
                prompt=traj_prompt + "\nReply valid JSON: {\"active_manipulation\": true/false, \"tools_opened\": true/false}"
            )
            parsed = bool_check.get("parsed", {})
            if parsed.get("active_manipulation") or parsed.get("tools_opened"):
                score += 30
                feedback_parts.append("✅ VLM confirmed workflow activity")
            else:
                feedback_parts.append("⚠️ VLM did not detect active manipulation")
        else:
            # Fallback if VLM fails
            score += 15 

    # Criterion C: Final Result Verification (30 points)
    # Analyze the user's specific screenshot output
    if user_screenshot_available:
        final_prompt = """
        This is a screenshot exported from Blue Sky Plan.
        It should show a dental CBCT scan (skull/teeth).
        
        Check the alignment:
        1. Sagittal View (usually top right or bottom left): Is the occlusal plane (teeth bite) horizontal?
        2. Coronal View (usually bottom right): Is the skull symmetric and upright?
        3. Axial View (usually top left): Is the dental arch a symmetric U-shape?
        
        Reply valid JSON:
        {
            "is_dental_scan": true,
            "alignment_looks_correct": true,
            "occlusal_plane_horizontal": true
        }
        """
        final_check = query_vlm(images=[temp_screenshot.name], prompt=final_prompt)
        parsed_final = final_check.get("parsed", {})
        
        if parsed_final.get("alignment_looks_correct") or parsed_final.get("occlusal_plane_horizontal"):
            score += 30
            feedback_parts.append("✅ Final alignment verified")
        elif parsed_final.get("is_dental_scan"):
            score += 10
            feedback_parts.append("⚠️ Scan visible but alignment imperfect")
        else:
            feedback_parts.append("❌ Screenshot content unclear")
            
        os.unlink(temp_screenshot.name)
    else:
        # Fallback: Check the final desktop screenshot if user file missing
        # This is less ideal as it might have UI overlays
        pass

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }