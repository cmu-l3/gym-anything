#!/usr/bin/env python3
"""
Verifier for process_price_override_sale task.

Verification Strategy:
1. File Evidence (40 pts):
   - Confirms data files were modified during task.
   - Checks for presence of specific strings ("V-LAMP", "Damaged cosmetic scratch") in the data files.
   
2. VLM Trajectory (60 pts):
   - Verifies the visual workflow:
     - Item creation with $150 price.
     - Adding item to sale.
     - Modifying price to $120 IN THE SALE (not globally).
     - Adding the note.
     - Completing payment.

Anti-Gaming:
- Requires files to be modified AFTER task start.
- Checks specifically for the note text which is unique to this transaction.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_price_override_sale(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve JSON result from Windows container
    # The path inside the container is C:\workspace\tasks\process_price_override_sale\task_result.json
    # We need to map that to the copy_from_env call.
    # Assuming the container maps paths correctly or using the linux-style path for the mount point if accessible.
    # Since env.json mounts /workspace/tasks, we try to access it there.
    # Note: Docker cp works on the container path. In Windows containers, C:\workspace mapped to /workspace.
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try copying from the mapped workspace path which is usually standardized
        copy_from_env("C:\\workspace\\tasks\\process_price_override_sale\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy result file: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result file from container."}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate File Evidence (40 points)
    score = 0
    feedback = []

    if result.get("app_running", False):
        score += 5
        feedback.append("App was running.")

    if result.get("files_modified_during_task", False):
        score += 10
        feedback.append("Data files modified.")
        
        # String checks
        if result.get("found_item_code", False):
            score += 10
            feedback.append("Item 'V-LAMP' found in data.")
        
        if result.get("found_note", False):
            score += 15
            feedback.append("Note 'Damaged cosmetic scratch' found in data.")
        else:
            feedback.append("Note text NOT found in data.")
    else:
        feedback.append("No data modifications detected (did you save?).")

    # 3. VLM Trajectory Verification (60 points)
    frames = sample_trajectory_frames(traj, n=6)
    
    prompt = """
    You are verifying a Point of Sale task. The user had to:
    1. Create an item 'V-LAMP' with price $150.00.
    2. Add it to a sale.
    3. Override the sale price to $120.00 (discounting it manually).
    4. Add a note: 'Damaged cosmetic scratch'.
    5. Process the cash payment.

    Review the screenshots and determine:
    A. Was the item 'V-LAMP' created or seen with a base price of $150?
    B. Was the price changed to $120 during the transaction?
    C. Is there visual evidence of the note 'Damaged cosmetic scratch' being entered?
    D. Was the sale completed (receipt, change due, or new sale screen)?

    Return JSON:
    {
        "item_created_150": boolean,
        "price_override_120": boolean,
        "note_added": boolean,
        "sale_completed": boolean,
        "explanation": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=prompt)
    
    if vlm_result and "parsed" in vlm_result:
        vlm_data = vlm_result["parsed"]
        
        if vlm_data.get("item_created_150", False):
            score += 15
            feedback.append("VLM: Item created with correct base price.")
        
        if vlm_data.get("price_override_120", False):
            score += 20
            feedback.append("VLM: Price override to $120 observed.")
        else:
            feedback.append("VLM: Could not confirm price override to $120.")

        if vlm_data.get("note_added", False):
            score += 10
            feedback.append("VLM: Note entry observed.")
            
        if vlm_data.get("sale_completed", False):
            score += 15
            feedback.append("VLM: Sale completion observed.")

    # 4. Final Scoring
    passed = score >= 70 and result.get("found_note", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }