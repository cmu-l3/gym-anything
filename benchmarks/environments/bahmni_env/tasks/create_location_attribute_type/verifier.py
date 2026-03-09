#!/usr/bin/env python3
"""
Verifier for create_location_attribute_type task.

Verifies:
1. Location Attribute Type exists in OpenMRS
2. Metadata matches requirements (Name, Description, Datatype, Multiplicity)
3. Item was created during the task window (Anti-gaming)
4. VLM verifies UI interaction (Secondary)
"""

import json
import os
import tempfile
import logging
from dateutil import parser
import datetime

# Import VLM helpers
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_location_attribute_type(traj, env_info, task_info):
    """
    Verify creation of 'Landline Extension' location attribute type.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get("expected_name", "Landline Extension")
    expected_desc = metadata.get("expected_description", "Internal telephone extension number")
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    attr_exists = result.get("attribute_exists", False)
    details = result.get("attribute_details", {})
    counts = result.get("counts", {})
    
    # --- CRITERION 1: Attribute Exists (40 pts) ---
    if attr_exists:
        score += 40
        feedback_parts.append("Attribute type created")
    else:
        feedback_parts.append("Attribute type NOT found")
        return {"passed": False, "score": 0, "feedback": "Failed: Attribute type not created"}

    # --- CRITERION 2: Name Exact Match (20 pts) ---
    # The API query in export script already filtered by name, but we double check
    if details.get("name") == expected_name:
        score += 20
        feedback_parts.append("Name matches")
    else:
        feedback_parts.append(f"Name mismatch (Expected: {expected_name}, Got: {details.get('name')})")

    # --- CRITERION 3: Datatype Check (20 pts) ---
    # OpenMRS datatypes can be java classes or config strings
    datatype = details.get("datatype", "")
    if "String" in datatype or "FreeText" in datatype or "java.lang.String" in datatype:
        score += 20
        feedback_parts.append("Datatype correct")
    else:
        feedback_parts.append(f"Datatype incorrect ({datatype})")

    # --- CRITERION 4: Description & Multiplicity (10 pts) ---
    desc_match = expected_desc.lower() in details.get("description", "").lower()
    min_match = str(details.get("min_occurs")) == "0"
    max_match = str(details.get("max_occurs")) == "1"
    
    sub_score = 0
    if desc_match: sub_score += 4
    if min_match: sub_score += 3
    if max_match: sub_score += 3
    
    score += sub_score
    if sub_score == 10:
        feedback_parts.append("Metadata details correct")
    else:
        feedback_parts.append("Metadata details partial mismatch")

    # --- CRITERION 5: Anti-Gaming (Timestamp/Count) (10 pts) ---
    # Check if newly created
    newly_created = False
    
    # Method A: Count increased
    if counts.get("current", 0) > counts.get("initial", 0):
        newly_created = True
    
    # Method B: Creation date after task start
    date_created_str = details.get("date_created")
    task_start_ts = result.get("task_start", 0)
    
    if date_created_str:
        try:
            # Parse ISO date string from OpenMRS
            created_dt = parser.parse(date_created_str)
            # Convert to unix timestamp (naive or aware)
            created_ts = created_dt.timestamp()
            if created_ts > task_start_ts:
                newly_created = True
        except Exception:
            pass
            
    if newly_created:
        score += 10
        feedback_parts.append("Verified new creation")
    else:
        feedback_parts.append("WARN: Could not verify new creation (timestamp/count check failed)")
        # We don't fail, but we don't give the anti-gaming points

    # --- VLM TRAJECTORY CHECK (Pass/Fail confirmation) ---
    # We use VLM to ensure the agent actually used the UI (OpenMRS Admin)
    # This detects if they just used a `curl` command from the terminal (unlikely but possible)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        if frames:
            prompt = """
            Look at these screenshots of a user interacting with OpenMRS/Bahmni.
            Did the user navigate to the 'Administration' page or 'Manage Location Attribute Types' screen?
            Does the interface look like the OpenMRS legacy admin UI (lists of links, simple HTML forms)?
            Answer YES or NO.
            """
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            if vlm_resp.get("success") and "YES" in vlm_resp.get("result", "").upper():
                feedback_parts.append("UI usage confirmed by VLM")
            else:
                feedback_parts.append("VLM did not clearly see Admin UI")

    # Final result
    passed = score >= 80  # Requires existence + name + datatype + most details
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }