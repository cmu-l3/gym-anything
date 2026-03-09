#!/usr/bin/env python3
"""
Verifier for design_outdoor_kitchen task (DreamPlan Home Design).

Verification Strategy:
1. File Verification: Checks if the user saved the requested screenshot and if it was created during the task.
2. VLM Visual Analysis (Primary): Analyzes the user's screenshot to identify:
   - Barbecue Grill
   - Dining Table
   - Chairs (Count >= 4)
   - Outdoor context (patio/grass)
3. VLM Workflow Analysis (Secondary): Checks trajectory to ensure the agent actually navigated menus 
   and placed items, rather than loading a pre-made file.

Scoring:
- Files exist & valid: 30 pts
- VLM Content (Grill + Table + Chairs): 50 pts
- VLM Workflow: 20 pts
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_outdoor_kitchen(traj, env_info, task_info):
    """
    Verify that the outdoor kitchen was designed correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    
    score = 0
    feedback_parts = []
    
    try:
        # Copy JSON
        try:
            copy_from_env("C:\\task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        # Check Screenshot Existence (30 pts)
        if result_data.get("screenshot_exists") and result_data.get("screenshot_created_during_task"):
            score += 20
            feedback_parts.append("Screenshot saved correctly.")
            
            # Retrieve the screenshot for VLM
            try:
                copy_from_env(result_data["screenshot_path"], temp_png.name)
                evidence_image = temp_png.name
            except:
                evidence_image = None
                feedback_parts.append("Warning: Could not retrieve saved screenshot for verification.")
        else:
            feedback_parts.append("Screenshot missing or not created during task.")
            
        # Check Project Save (10 pts)
        if result_data.get("project_was_saved"):
            score += 10
            feedback_parts.append("Project changes saved.")
        else:
            feedback_parts.append("Project not saved.")

        # 2. VLM Visual Analysis of Result (50 pts)
        if evidence_image:
            vlm_prompt = (
                "Analyze this screenshot of a home design software 3D view. "
                "I am looking for an outdoor kitchen setup on a patio or backyard. "
                "Check for the following items:\n"
                "1. A Barbecue Grill (BBQ).\n"
                "2. A Dining Table.\n"
                "3. Chairs around the table (count them).\n"
                "4. Is the setting outdoors (grass, sky, patio texturing)?\n\n"
                "Return JSON: {\"has_grill\": bool, \"has_table\": bool, \"chair_count\": int, \"is_outdoors\": bool}"
            )
            
            vlm_response = query_vlm(prompt=vlm_prompt, image=evidence_image)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("has_grill"):
                    score += 15
                    feedback_parts.append("Grill detected.")
                else:
                    feedback_parts.append("No grill detected.")
                    
                if parsed.get("has_table"):
                    score += 15
                    feedback_parts.append("Table detected.")
                else:
                    feedback_parts.append("No table detected.")
                    
                chairs = parsed.get("chair_count", 0)
                if chairs >= 4:
                    score += 10
                    feedback_parts.append(f"Chairs detected ({chairs}).")
                elif chairs >= 1:
                    score += 5
                    feedback_parts.append(f"Not enough chairs ({chairs}/4).")
                else:
                    feedback_parts.append("No chairs detected.")
                    
                if parsed.get("is_outdoors"):
                    score += 10
                    feedback_parts.append("Correct outdoor context.")
                else:
                    feedback_parts.append("Scene does not appear to be outdoors.")

        # 3. VLM Trajectory Verification (20 pts)
        # We check if the agent actually used the furniture catalog
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            traj_prompt = (
                "Review these screenshots of a user using DreamPlan Home Design Software. "
                "Did the user:\n"
                "1. Open a furniture catalog or library?\n"
                "2. Navigate to 'Exterior', 'Outdoor', or 'Patio' categories?\n"
                "3. Perform actions to place objects?\n"
                "Return JSON: {\"opened_catalog\": bool, \"exterior_category\": bool, \"placement_action\": bool}"
            )
            
            traj_response = query_vlm(prompt=traj_prompt, images=frames)
            if traj_response.get("success"):
                t_parsed = traj_response.get("parsed", {})
                if t_parsed.get("opened_catalog") or t_parsed.get("placement_action"):
                    score += 20
                    feedback_parts.append("Workflow verified via trajectory.")
                else:
                    feedback_parts.append("No furniture placement workflow observed in trajectory.")
        
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_png.name):
            os.unlink(temp_png.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }