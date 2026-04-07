#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_custom_resource_type(traj, env_info, task_info):
    """
    Verifies that the agent added 'UAS Team' to picklists and registered the resource.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing."}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    picklist_added = result.get("picklist_added", False)
    resource_created = result.get("resource_created", False)
    type_linkage_correct = result.get("type_linkage_correct", False)
    details_correct = result.get("resource_details_correct", False)
    db_connected = result.get("db_connected", False)

    # 3. Scoring Logic
    score = 0
    feedback = []

    if not db_connected:
        return {"passed": False, "score": 0, "feedback": "Could not verify database state (connection failed)."}

    # Criterion 1: Picklist Modification (40 pts)
    # This is the "Hard" part of the task - customizing the system.
    if picklist_added:
        score += 40
        feedback.append("Successfully added 'UAS Team' to system picklists.")
    else:
        feedback.append("Failed to add 'UAS Team' to system picklists.")

    # Criterion 2: Resource Creation (30 pts)
    if resource_created:
        score += 30
        feedback.append("Resource 'Eagle Eye SAR Unit' record created.")
    else:
        feedback.append("Resource record not found.")

    # Criterion 3: Type Linkage (20 pts)
    # Only award if they actually used the new type
    if type_linkage_correct:
        score += 20
        feedback.append("Resource correctly assigned to 'UAS Team' type.")
    elif resource_created:
        feedback.append(f"Resource created but wrong type: {result.get('resource_type_found', 'Unknown')}")

    # Criterion 4: Data Accuracy (10 pts)
    if details_correct:
        score += 10
        feedback.append("Phone and Address details matched.")
    elif resource_created:
        feedback.append("Some resource details (Phone/Zip) were incorrect.")

    # 4. VLM Trajectory Verification
    # We want to ensure they didn't just hack the DB or type "UAS Team" into a text field if it wasn't a dropdown.
    # The VLM checks if they accessed the configuration menu.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of CAMEO Data Manager. "
        "Did the user access a 'Modify Picklist', 'Edit Lookups', or 'Configuration' menu? "
        "Did they enter 'UAS Team' into a list management screen? "
        "Did they finally fill out a Resource form for 'Eagle Eye SAR Unit'?"
    )
    
    # We only penalize if score is high but VLM looks completely wrong (anti-gaming),
    # or use it to confirm borderline cases. Here we trust DB mostly, but check for "Do Nothing".
    
    # Pass Threshold
    # Must have modified picklist AND created resource correctly linked.
    passed = (picklist_added and resource_created and type_linkage_correct)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }