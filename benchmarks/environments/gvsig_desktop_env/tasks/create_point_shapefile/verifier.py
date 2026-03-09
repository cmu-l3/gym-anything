#!/usr/bin/env python3
"""
Verifier for create_point_shapefile task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_point_shapefile(traj, env_info, task_info):
    """
    Verifies the creation of a point shapefile with specific attributes.
    
    Scoring Breakdown (100 pts total):
    1. File Existence & Validity (30 pts)
       - .shp, .shx, .dbf exist (10)
       - Created during task timestamp check (5)
       - Geometry type is Point (15)
    2. Schema Definition (20 pts)
       - site_name field exists (7)
       - site_type field exists (7)
       - priority field exists (6)
    3. Data Content (40 pts)
       - 3 records total (10)
       - Record 1 matches (10)
       - Record 2 matches (10)
       - Record 3 matches (10)
    4. VLM Workflow Check (10 pts)
       - Did the agent use the UI correctly?
    """
    
    # 1. Retrieve result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Validity (30 pts) ---
    if result.get("file_exists"):
        score += 10
        feedback.append("Shapefile components (.shp, .shx, .dbf) found.")
    else:
        feedback.append("Missing Shapefile components. Found: " + str(result.get("extensions_exist")))
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if result.get("file_created_during_task"):
        score += 5
    else:
        feedback.append("Warning: File timestamp indicates it wasn't created during this session.")

    geom_type = result.get("geometry_type")
    if geom_type == "Point":
        score += 15
        feedback.append("Correct geometry type (Point).")
    else:
        feedback.append(f"Incorrect geometry type: {geom_type} (Expected Point).")

    # --- Criterion 2: Schema Definition (20 pts) ---
    # Field names are normalized to lowercase in export_result.sh
    fields = [f.lower() for f in result.get("field_names", [])]
    
    required_fields = ["site_name", "site_type", "priority"]
    missing_fields = []
    
    for req in required_fields:
        # Simple substring match or exact match
        if any(req in f for f in fields):
            score += round(20 / len(required_fields))
        else:
            missing_fields.append(req)
            
    if not missing_fields:
        feedback.append("Schema definition correct.")
    else:
        feedback.append(f"Missing attributes: {', '.join(missing_fields)}.")

    # --- Criterion 3: Data Content (40 pts) ---
    records = result.get("records", [])
    if len(records) == 3:
        score += 10
        feedback.append("Correct record count (3).")
    else:
        feedback.append(f"Incorrect record count: {len(records)} (Expected 3).")

    # Verify specific rows
    # We look for matches in the dataset regardless of order
    expected_data = [
        {"site_name": "alpha station", "site_type": "weather", "priority": 1},
        {"site_name": "beta outpost", "site_type": "seismic", "priority": 2},
        {"site_name": "gamma point", "site_type": "tidal", "priority": 3}
    ]
    
    matches_found = 0
    for expected in expected_data:
        found = False
        for actual in records:
            # Check for rough match (case insensitive string, exact int)
            name_match = expected["site_name"] in str(actual.get("site_name", "")).lower()
            type_match = expected["site_type"] in str(actual.get("site_type", "")).lower()
            
            # Priority might be int or float or string depending on parsing
            act_p = actual.get("priority", -1)
            try:
                p_match = int(float(act_p)) == expected["priority"]
            except:
                p_match = False
                
            if name_match and type_match and p_match:
                found = True
                break
        if found:
            matches_found += 1
            
    score += (matches_found * 10)
    if matches_found == 3:
        feedback.append("All attribute data correct.")
    else:
        feedback.append(f"Matched {matches_found}/3 records correctly.")

    # --- Criterion 4: VLM Workflow Check (10 pts) ---
    # If the programmatic score is high, we check VLM to confirm no cheating (like standard copy-paste)
    # though file timestamp helps. We mainly check if they used the UI.
    if score >= 60:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        vlm_prompt = (
            "Review these screenshots of a gvSIG Desktop user session. "
            "The user should be creating a new Shapefile and adding points. "
            "Look for: 1) 'New Layer' or 'New Shapefile' dialogs, "
            "2) Editing mode (pencil icon active or points being placed), "
            "3) Attribute table or input form interaction. "
            "Does the workflow look legitimate?"
        )
        
        try:
            vlm_response = query_vlm(frames + [final_img], vlm_prompt).lower()
            if "yes" in vlm_response or "legitimate" in vlm_response or "correct" in vlm_response:
                score += 10
            else:
                feedback.append("VLM Verification: Workflow ambiguous.")
                score += 5 # Give benefit of doubt if VLM is unsure but file exists
        except Exception:
            # Fallback if VLM fails
            score += 10
    else:
        feedback.append("Skipping VLM check due to low programmatic score.")

    # Final tally
    passed = (score >= 70) and result.get("file_exists")
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }