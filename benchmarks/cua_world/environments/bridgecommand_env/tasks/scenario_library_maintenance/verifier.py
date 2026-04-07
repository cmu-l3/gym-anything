#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_scenario_library_maintenance(traj, env_info, task_info):
    """
    Verify the scenario library maintenance task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Quarantine Logic (25 points)
    # Fatal scenario must be gone from Scenarios and present in Quarantine
    fatal = result.get("fatal_scenario", {})
    if not fatal.get("in_scenarios") and fatal.get("in_quarantine"):
        score += 25
        feedback_parts.append("Quarantine logic correct")
    elif fatal.get("in_quarantine"):
        score += 15
        feedback_parts.append("Quarantine successful but original might exist?")
    else:
        feedback_parts.append("FAIL: Fatal scenario not quarantined")

    # 2. Repair Logic - Tug (20 points)
    # "Old_Steam_Tug_v1" should be replaced by "Tug"
    tug = result.get("tug_scenario", {})
    # Loose matching for "Tug" (case insensitive handled by script, but here we check value)
    val_tug = tug.get("type_1_value", "").lower()
    if "tug" in val_tug and "old" not in val_tug: # Ensure it was changed to the target
        score += 20
        feedback_parts.append("Tug substitution correct")
    elif "old" in val_tug:
        feedback_parts.append("FAIL: Tug scenario not modified")
    else:
        feedback_parts.append(f"FAIL: Tug scenario has unexpected value '{val_tug}'")

    # 3. Repair Logic - Generic (20 points)
    # "Mystery_Cargo_Vessel_2000" should be replaced by "Coaster"
    gen = result.get("generic_scenario", {})
    val_gen = gen.get("type_1_value", "").lower()
    if "coaster" in val_gen:
        score += 20
        feedback_parts.append("Fallback substitution (Coaster) correct")
    elif "mystery" in val_gen:
        feedback_parts.append("FAIL: Generic scenario not modified")
    else:
        feedback_parts.append(f"FAIL: Generic scenario has unexpected value '{val_gen}'")

    # 4. Preservation (15 points)
    # Valid scenario should still exist and shipname unchanged
    valid = result.get("valid_scenario", {})
    if valid.get("exists") and "ferry" in valid.get("ownship_value", "").lower():
        score += 15
        feedback_parts.append("Valid scenario preserved")
    else:
        feedback_parts.append("FAIL: Valid scenario damaged or moved")

    # 5. Metadata Creation (10 points)
    # Check if descriptions exist where they were missing
    # Tug and Valid had missing descriptions. Generic had one existing.
    meta_score = 0
    if tug.get("description_exists"): meta_score += 5
    if valid.get("description_exists"): meta_score += 5
    
    if meta_score == 10:
        feedback_parts.append("Metadata creation correct")
    elif meta_score > 0:
        feedback_parts.append("Partial metadata creation")
    score += meta_score

    # 6. Reporting (10 points)
    if result.get("report_exists"):
        score += 10
        feedback_parts.append("Report generated")
    else:
        feedback_parts.append("FAIL: No report file")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }