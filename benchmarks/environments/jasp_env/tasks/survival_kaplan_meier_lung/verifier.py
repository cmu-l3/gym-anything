#!/usr/bin/env python3
"""
Verifier for Survival Analysis (Kaplan-Meier) task in JASP.
Checks if the agent correctly loaded data, converted variable types,
configured the survival analysis, and defined the event level correctly.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_survival_analysis(traj, env_info, task_info):
    """
    Verify the JASP project file contains a correctly configured Kaplan-Meier analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence & Timestamp (Anti-gaming)
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file LungSurvival.jasp not found."}
    
    if not result_data.get('file_created_during_task', False):
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during this task.")
        # We proceed but with a penalty or skepticism, handled by score logic below
    else:
        score += 10
        feedback_parts.append("File created/saved successfully.")

    # 3. Retrieve and Inspect JASP File
    jasp_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    jasp_temp.close()
    
    try:
        # Copy the JASP file (which is a zip) from container
        exported_path = result_data.get('exported_file_path', '/tmp/LungSurvival_export.jasp')
        copy_from_env(exported_path, jasp_temp.name)
        
        if not zipfile.is_zipfile(jasp_temp.name):
            return {"passed": False, "score": score, "feedback": "Saved file is not a valid JASP/Zip archive."}

        # Extract analyses.json (and potentially metadata)
        with zipfile.ZipFile(jasp_temp.name, 'r') as z:
            file_list = z.namelist()
            if 'analyses.json' not in file_list:
                return {"passed": False, "score": score, "feedback": "Invalid JASP file: analyses.json missing."}
            
            with z.open('analyses.json') as f:
                analyses_data = json.load(f)

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error inspecting JASP file: {e}"}
    finally:
        if os.path.exists(jasp_temp.name):
            os.unlink(jasp_temp.name)

    # 4. Verify Analysis Configuration
    # We look for a "jaspSurvival" or "KaplanMeier" entry
    km_analysis = None
    for analysis in analyses_data:
        # JASP structure varies slightly by version but usually has "name" or "title" or "qta" (Qt Analysis)
        # We look for identification of the module
        analysis_str = json.dumps(analysis)
        if "KaplanMeier" in analysis_str or "jaspSurvival" in analysis_str:
            km_analysis = analysis
            break
            
    if not km_analysis:
        return {"passed": False, "score": score, "feedback": "No Kaplan-Meier Survival analysis found in project."}
    
    score += 10
    feedback_parts.append("Kaplan-Meier analysis found.")
    
    # Inspect Settings
    settings = km_analysis.get('settings', {})
    
    # Check Variable Assignments
    # Note: Keys depend on JASP version. Common patterns: "time", "event", "strata"/"factor"
    
    # Check Time Variable
    time_var = settings.get('time', [])
    if time_var == "time" or (isinstance(time_var, list) and "time" in time_var):
        score += 10
        feedback_parts.append("Time variable assigned correctly.")
    else:
        feedback_parts.append(f"Incorrect Time variable: {time_var}")

    # Check Event Variable
    event_var = settings.get('event', [])
    if event_var == "status" or (isinstance(event_var, list) and "status" in event_var):
        score += 10
        feedback_parts.append("Event variable assigned correctly.")
    else:
        feedback_parts.append(f"Incorrect Event variable: {event_var}")

    # Check Strata/Factor (Sex)
    # This implicitly tests the Variable Type Cast, because JASP often prevents Scale vars in Factor fields
    strata_var = settings.get('strata', [])
    if not strata_var:
         strata_var = settings.get('factor', []) # Alternative key
         
    if strata_var == "sex" or (isinstance(strata_var, list) and "sex" in strata_var):
        score += 30 # High points because it requires Type Casting
        feedback_parts.append("Strata variable (sex) assigned correctly (implies type conversion).")
    else:
        feedback_parts.append(f"Incorrect Strata variable: {strata_var}")

    # Check Event Level Definition
    # This is often stored as "eventLevel": "2" or similar
    # Sometimes it is part of a "levels" dict. We search loosely if key exact match fails.
    event_level_correct = False
    
    if str(settings.get('eventLevel', '')).strip() == "2":
        event_level_correct = True
    elif "2" in str(settings.get('eventLevel', '')): 
        # Sometimes stored as value "2" inside a complex object
        event_level_correct = True
        
    if event_level_correct:
        score += 20
        feedback_parts.append("Event level correctly set to '2' (Death).")
    else:
        feedback_parts.append(f"Event level check failed. Value found: {settings.get('eventLevel', 'N/A')}")

    # Check for Log-rank test (default usually, but good to check)
    # Often stored in results/tables requests, or "logRank" setting
    if settings.get('logRank', True): # If it's boolean true or default
        score += 10
        feedback_parts.append("Log-rank test enabled.")

    # Final Evaluation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }