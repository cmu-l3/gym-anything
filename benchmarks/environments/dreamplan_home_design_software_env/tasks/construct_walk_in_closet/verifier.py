#!/usr/bin/env python3
"""
Verifier for Construct Walk-in Closet task.

Verification Strategy:
1. File Verification (Anti-gaming):
   - Checks if a DreamPlan project file (.dpp) was modified/saved after task start.
   - Checks if the file size is non-zero.

2. VLM Trajectory Verification (Process):
   - Verifies the agent used the 'Wall' tool (or 'Partition').
   - Verifies the agent used the 'Door' tool.
   - Verifies the agent accessed 'Furniture'/'Storage'.

3. VLM Final State Verification (Outcome):
   - Checks for a "room within a room" structure (closet walls).
   - Checks for a door connecting the spaces.
   - Checks for visible shelving/storage inside.

Scoring:
- 10 pts: Project Saved (File check)
- 30 pts: Walls Created (VLM)
- 20 pts: Door Installed (VLM)
- 20 pts: Storage Added (VLM)
- 20 pts: Correct Placement/Workflow (VLM trajectory)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_construct_walk_in_closet(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve File-based Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path C:\tmp\task_result.json was mapped to this location in export script
        # The copy_from_env usually handles the path translation if the container path is provided
        # For Windows containers, usually providing the absolute internal path works.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            file_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        file_result = {}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Prepare VLM Inputs
    frames = sample_trajectory_frames(traj, n=6)
    final_screen = get_final_screenshot(traj)
    
    if not final_screen:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    all_images = frames + [final_screen]

    # 3. VLM Query
    prompt = """
    You are verifying a task in a Home Design software (DreamPlan).
    The user was asked to: "Construct a walk-in closet in the Master Bedroom".
    
    Requirements:
    1. CREATE WALLS: New partition walls creating a small enclosed room inside a larger bedroom.
    2. INSTALL DOOR: A door connecting the new closet to the bedroom.
    3. ADD STORAGE: Shelves, wardrobe, or hanging rods inside the new space.
    
    Review the sequence of images (trajectory) and the final image.
    
    Answer the following questions in JSON format:
    {
        "walls_tool_used": boolean, // Did you see the user select/use the Wall tool?
        "furniture_tool_used": boolean, // Did you see the user select/use Furniture/Storage?
        "new_enclosure_visible": boolean, // Is there a new small room/enclosure visible in the final plan?
        "door_visible": boolean, // Is there a door on the new wall?
        "storage_item_visible": boolean, // Is there a shelf/wardrobe inside the new space?
        "master_bedroom_context": boolean, // Does it look like it's inside a bedroom (bed visible nearby)?
        "feedback": "string explaining what was observed"
    }
    """

    vlm_response = query_vlm(images=all_images, prompt=prompt)
    
    try:
        vlm_data = vlm_response.get("parsed", {})
    except:
        vlm_data = {}
        
    logger.info(f"VLM Analysis: {vlm_data}")

    # 4. Scoring Logic
    score = 0
    feedback_items = []

    # Criterion: Project Saved (10 pts)
    if file_result.get("file_modified", False) and file_result.get("modified_file_size", 0) > 1000:
        score += 10
        feedback_items.append("Project file saved successfully.")
    else:
        feedback_items.append("Project file NOT saved or no changes detected.")

    # Criterion: Walls Created / Enclosure (30 pts)
    if vlm_data.get("new_enclosure_visible", False):
        score += 30
        feedback_items.append("Walk-in closet enclosure (walls) constructed.")
    else:
        feedback_items.append("No new wall enclosure visible.")

    # Criterion: Door Installed (20 pts)
    if vlm_data.get("door_visible", False):
        score += 20
        feedback_items.append("Door installed for closet.")
    else:
        feedback_items.append("No door visible on the closet.")

    # Criterion: Storage Added (20 pts)
    if vlm_data.get("storage_item_visible", False):
        score += 20
        feedback_items.append("Storage/shelving added inside closet.")
    else:
        feedback_items.append("No storage items visible inside.")

    # Criterion: Workflow/Trajectory (20 pts)
    # Check if tools were used properly
    tools_score = 0
    if vlm_data.get("walls_tool_used", False): tools_score += 10
    if vlm_data.get("furniture_tool_used", False): tools_score += 10
    
    score += tools_score
    if tools_score > 0:
        feedback_items.append(f"Tools usage verified ({tools_score}/20 pts).")

    # Anti-gaming check: If score > 0 but file not saved, reduce score (must save work)
    if score > 0 and not file_result.get("file_modified", False):
        score = max(0, score - 20)
        feedback_items.append("PENALTY: Work done but not saved.")

    passed = score >= 60 and vlm_data.get("new_enclosure_visible", False) and vlm_data.get("door_visible", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_items)
    }