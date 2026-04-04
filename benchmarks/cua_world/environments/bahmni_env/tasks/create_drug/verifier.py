#!/usr/bin/env python3
"""
Verifier for create_drug task (Bahmni/OpenMRS).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_drug(traj, env_info, task_info):
    """
    Verify that the drug was created correctly in OpenMRS.
    
    Criteria:
    1. Drug exists in database/API with correct name "Amoxicillin 500mg Capsule".
    2. Strength is "500mg".
    3. Concept is linked to "AMOXICILLIN".
    4. Combination is false.
    5. Drug was created AFTER the task started (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Amoxicillin 500mg Capsule")
    expected_strength = metadata.get('expected_strength', "500mg")
    
    # Load result from container
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
    max_score = 100
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    
    # --- Check 1: API Verification (Primary) ---
    api_data = result.get('api_verification', {})
    
    if not api_data.get('found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Drug 'Amoxicillin 500mg Capsule' not found via OpenMRS API."
        }
    
    score += 30
    feedback_parts.append("Drug found via API")
    
    # Check Details
    # Name (already checked by finding it, but verifying exactness)
    actual_name = api_data.get('name', '')
    if actual_name.strip() == expected_name:
        score += 10
        feedback_parts.append("Name matches exactly")
    else:
        feedback_parts.append(f"Name mismatch ('{actual_name}')")
        
    # Strength
    # API might return null if not set, or string
    actual_strength = api_data.get('strength', '')
    # Allow some flex: "500mg", "500 mg", "500MG"
    if actual_strength and actual_strength.lower().replace(" ", "") == expected_strength.lower().replace(" ", ""):
        score += 20
        feedback_parts.append("Strength correct")
    else:
        feedback_parts.append(f"Strength incorrect (expected '{expected_strength}', got '{actual_strength}')")

    # Combination
    combination = api_data.get('combination')
    if combination is False or combination == "false" or combination == 0:
        score += 10
        feedback_parts.append("Combination flag correct (False)")
    else:
        feedback_parts.append(f"Combination flag incorrect ({combination})")
        
    # Concept Linkage
    concept_display = api_data.get('concept_display', '')
    if "AMOXICILLIN" in concept_display.upper():
        score += 20
        feedback_parts.append("Linked to correct concept")
    else:
        feedback_parts.append(f"Incorrect concept link ('{concept_display}')")

    # --- Check 2: Database Cross-Verification & Anti-Gaming ---
    db_data = result.get('db_verification', {})
    
    if db_data.get('found'):
        score += 10
        feedback_parts.append("Confirmed in Database")
        
        # Check timestamp
        created_ts = db_data.get('created_timestamp', 0)
        # Allow small clock skew (e.g. 60s before start if clocks drifted, though they are on same VM)
        # Ideally created_ts > task_start
        if created_ts >= task_start - 5:
            feedback_parts.append("Creation time verified")
        else:
            score -= 50 # Heavy penalty for pre-existing data
            feedback_parts.append("FAIL: Drug appears to have been created before task started!")
    else:
        feedback_parts.append("Warning: Not found in direct DB query (API/DB mismatch?)")

    passed = score >= 60 and api_data.get('found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }