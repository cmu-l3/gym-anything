#!/usr/bin/env python3
"""
Verifier for verify_landscape_layout task.

CRITERIA:
1. Landscape screenshot exists and has valid landscape dimensions (Width > Height).
2. Flight Crew View app is visible in the landscape screenshot (VLM check).
3. Device rotation was restored to Portrait at the end.
4. Report file exists with correct content.
"""

import json
import os
import tempfile
import logging
from PIL import Image
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_landscape_layout(traj, env_info, task_info):
    """
    Verifies that the agent rotated the screen, captured a landscape screenshot,
    and restored the state.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Temp file management
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    try:
        # 1. Fetch Result JSON
        try:
            copy_from_env("/sdcard/task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}

        # 2. Analyze Screenshot (Geometry)
        proof_exists = result_data.get("proof_exists", False)
        is_landscape_dims = False
        
        if proof_exists:
            try:
                copy_from_env("/sdcard/landscape_proof.png", temp_img.name)
                with Image.open(temp_img.name) as img:
                    width, height = img.size
                    if width > height:
                        is_landscape_dims = True
                        score += 30
                        feedback_parts.append(f"Valid landscape screenshot ({width}x{height})")
                    else:
                        feedback_parts.append(f"Screenshot is portrait ({width}x{height})")
            except Exception as e:
                feedback_parts.append(f"Failed to analyze screenshot: {e}")
        else:
            feedback_parts.append("Landscape proof screenshot missing")

        # 3. VLM Analysis: App Visibility in Landscape Screenshot
        vlm_passed = False
        if is_landscape_dims:
            prompt = """
            Look at this screenshot. 
            1. Is the screen orientation landscape (wider than it is tall)?
            2. Is the 'Flight Crew View' app visible (look for flight lists, crew chat, or settings)?
            3. Is there any 'App has stopped' or crash dialog visible?
            
            Return JSON: {"landscape": bool, "app_visible": bool, "crashed": bool}
            """
            
            # Use the screenshot captured by the agent
            vlm_result = query_vlm(
                images=[temp_img.name],
                prompt=prompt
            )
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("landscape") and parsed.get("app_visible") and not parsed.get("crashed"):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("VLM confirms app visible and stable in landscape")
                else:
                    feedback_parts.append(f"VLM check failed: {parsed}")
            else:
                feedback_parts.append("VLM query failed")

        # 4. Check Restoration
        if result_data.get("rotation_restored"):
            score += 10
            feedback_parts.append("Rotation restored to portrait")
        else:
            feedback_parts.append("Failed to restore portrait mode")

        # 5. Check Report File
        report_exists = result_data.get("report_exists")
        report_content = result_data.get("report_content", "").strip().lower()
        
        if report_exists:
            score += 10
            if "rotated: yes" in report_content:
                score += 10
                feedback_parts.append("Report content correct")
            else:
                feedback_parts.append(f"Report content incorrect: '{report_content}'")
        else:
            feedback_parts.append("Report file missing")

        # 6. Check App Running Status
        if result_data.get("app_running"):
            score += 10
            feedback_parts.append("App remained running")
        else:
            feedback_parts.append("App crashed or closed")

        # 7. Trajectory Verification (Did they actually change settings?)
        # We sample frames to see if the settings panel or shell command usage was visible
        traj_frames = sample_trajectory_frames(traj, n=5)
        if traj_frames:
            # Simple bonus for non-empty trajectory
            score += 10
            feedback_parts.append("Workflow trajectory recorded")

    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    passed = (score >= 80) and is_landscape_dims and vlm_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }