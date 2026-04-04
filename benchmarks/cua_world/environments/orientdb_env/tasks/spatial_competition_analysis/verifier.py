#!/usr/bin/env python3
"""
Verifier for spatial_competition_analysis task.

Verifies:
1. Schema: 'CompetitionScore' property exists on 'Hotels' class (INTEGER).
2. Index: A SPATIAL index exists on 'Hotels'.
3. Function: 'CalculateCompetition' function exists in the database.
4. Logic/Data: Specific hotels have the correct CompetitionScore based on the setup data.
   - Hotel Artemide: 3 competitors (Rome cluster)
   - The Savoy: 2 competitors (London cluster)
   - Park Hyatt Tokyo: 0 competitors
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_competition_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- 1. Schema Verification (10 pts) ---
    schema = result.get("schema", {})
    classes = schema.get("classes", [])
    hotels_class = next((c for c in classes if c["name"] == "Hotels"), None)
    
    prop_valid = False
    if hotels_class:
        properties = hotels_class.get("properties", [])
        comp_prop = next((p for p in properties if p["name"] == "CompetitionScore"), None)
        if comp_prop:
            if comp_prop.get("type") == "INTEGER":
                score += 10
                prop_valid = True
                feedback_parts.append("Schema property 'CompetitionScore' (INTEGER) exists.")
            else:
                feedback_parts.append(f"Property 'CompetitionScore' exists but type is {comp_prop.get('type')} (expected INTEGER).")
        else:
            feedback_parts.append("Property 'CompetitionScore' not found on Hotels class.")
    else:
        feedback_parts.append("Class 'Hotels' not found (critical error).")

    # --- 2. Index Verification (15 pts) ---
    index_valid = False
    if hotels_class:
        indexes = hotels_class.get("indexes", [])
        # Look for any index with type SPATIAL
        spatial_idx = next((idx for idx in indexes if idx.get("type") == "SPATIAL"), None)
        if spatial_idx:
            score += 15
            index_valid = True
            feedback_parts.append(f"SPATIAL index '{spatial_idx['name']}' found.")
        else:
            feedback_parts.append("No SPATIAL index found on Hotels class.")

    # --- 3. Function Verification (20 pts) ---
    func_data = result.get("function_def", {}).get("result", [])
    func_valid = False
    if func_data and len(func_data) > 0:
        score += 20
        func_valid = True
        feedback_parts.append("Function 'CalculateCompetition' exists.")
    else:
        feedback_parts.append("Function 'CalculateCompetition' not found in database.")

    # --- 4. Logic/Data Verification (55 pts) ---
    # Targets: Artemide (3), Savoy (2), Park Hyatt (0)
    # Weights: Artemide (25), Savoy (20), Park Hyatt (10)
    
    hotels_data = result.get("hotels_data", {}).get("result", [])
    hotel_map = {h.get("Name"): h.get("CompetitionScore") for h in hotels_data}
    
    logic_score = 0
    
    # Hotel Artemide
    val_artemide = hotel_map.get("Hotel Artemide")
    if val_artemide == 3:
        logic_score += 25
        feedback_parts.append("Hotel Artemide score correct (3).")
    else:
        feedback_parts.append(f"Hotel Artemide score incorrect: got {val_artemide}, expected 3.")

    # The Savoy
    val_savoy = hotel_map.get("The Savoy")
    if val_savoy == 2:
        logic_score += 20
        feedback_parts.append("The Savoy score correct (2).")
    else:
        feedback_parts.append(f"The Savoy score incorrect: got {val_savoy}, expected 2.")

    # Park Hyatt Tokyo
    val_tokyo = hotel_map.get("Park Hyatt Tokyo")
    # Accept None as 0 (if user didn't init properly but logic technically works for empty)
    # But strictly, the task said "update... with this count", so 0 is better.
    if val_tokyo == 0 or val_tokyo is None: 
        # Being lenient on None if they initialized with NULL and count was 0
        if val_tokyo == 0:
            logic_score += 10
            feedback_parts.append("Park Hyatt Tokyo score correct (0).")
        else:
            logic_score += 5
            feedback_parts.append("Park Hyatt Tokyo score is NULL (expected 0).")
    else:
        feedback_parts.append(f"Park Hyatt Tokyo score incorrect: got {val_tokyo}, expected 0.")

    score += logic_score

    # Final Check
    passed = (score >= 65) and prop_valid and func_valid and (logic_score >= 25)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }