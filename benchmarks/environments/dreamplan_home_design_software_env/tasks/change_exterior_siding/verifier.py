#!/usr/bin/env python3
"""
Verifier for change_exterior_siding task in DreamPlan Home Design.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import framework VLM utilities if available
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=1): return []
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying a home design task. The user was asked to change the exterior wall material of a house to BRICK.

Analyze the image provided (screenshot of 3D home design software):
1. Is this an exterior view of a house?
2. Look at the ground floor exterior walls. Do they have a BRICK texture/pattern?
   - Distinct rectangular blocks with mortar lines
   - Reddish/brownish color typical of brick (though painted brick is possible, standard brick is expected)
   - NOT horizontal siding (long thin strips)
   - NOT plain stucco/plaster (smooth)
3. Is the image valid (not black/empty)?

Respond in JSON:
{
    "is_exterior_view": true/false,
    "has_brick_texture": true/false,
    "brick_confidence": "low/medium/high",
    "is_default_siding": true/false,
    "reasoning": "description of what you see on the walls"
}
"""

def verify_change_exterior_siding(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the exterior siding was changed to brick.
    
    Strategy:
    1. File Check: Confirm output screenshot exists and was created during task.
    2. Project Check: Confirm project files were modified (work was done).
    3. Visual Check (VLM): Analyze the output screenshot for brick texture.
    """
    
    # 1. Setup feedback and scoring
    score = 0
    feedback_parts = []
    
    # 2. Retrieve JSON result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy from Windows path inside container
        # Note: Docker cp works with the path format inside the container
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Evaluate File Evidence (40 points)
    output_exists = result_data.get("output_exists", False)
    file_fresh = result_data.get("file_created_during_task", False)
    file_size = result_data.get("output_size_bytes", 0)
    project_mod = result_data.get("project_modified", False)

    if output_exists and file_size > 5000: # Min valid image size
        score += 15
        feedback_parts.append("Screenshot saved successfully")
        if file_fresh:
            score += 15
            feedback_parts.append("Screenshot created during task session")
        else:
            feedback_parts.append("Warning: Screenshot timestamp predates task")
    else:
        feedback_parts.append("No valid screenshot found")

    if project_mod:
        score += 10
        feedback_parts.append("Project modification detected")
    else:
        feedback_parts.append("Warning: No changes saved to project file")

    # 4. Evaluate Visual Evidence via VLM (60 points)
    # We prefer the file the agent explicitly saved, as it represents their "final answer"
    # But we can fall back to the framework's final screenshot if needed.
    
    # Note: Since the agent saved a specific file "exterior_brick_result.png", 
    # ideally we would pull that file out to verify. However, `traj` usually contains
    # framework screenshots. We will use the framework's final screenshot as a proxy
    # for what was on screen, or if possible, `get_final_screenshot` which returns the last frame.
    
    final_frame = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_frame:
        vlm_resp = query_vlm(prompt=VLM_PROMPT, image=final_frame)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            
            is_exterior = parsed.get("is_exterior_view", False)
            has_brick = parsed.get("has_brick_texture", False)
            is_default = parsed.get("is_default_siding", False)
            
            if is_exterior:
                vlm_score += 20
                feedback_parts.append("VLM confirms exterior view")
            else:
                feedback_parts.append("VLM did not detect exterior view")
                
            if has_brick:
                vlm_score += 40
                feedback_parts.append("VLM confirms brick texture applied")
            elif is_default:
                feedback_parts.append("VLM detected default siding (task failed)")
            else:
                feedback_parts.append("VLM could not clearly identify brick texture")
                
            feedback_parts.append(f"VLM Note: {parsed.get('reasoning', '')}")
        else:
            feedback_parts.append("VLM verification failed to run")
    else:
        feedback_parts.append("No trajectory screenshots available for visual verification")

    score += vlm_score

    # 5. Final Pass Determination
    # Pass if: File exists AND VLM sees brick (min 75 points implies both major steps worked)
    passed = (score >= 70) and output_exists and (vlm_score >= 30)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }