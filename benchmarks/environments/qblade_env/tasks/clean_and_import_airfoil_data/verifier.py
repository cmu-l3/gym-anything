#!/usr/bin/env python3
"""
Verifier for clean_and_import_airfoil_data task.

SCORING CRITERIA:
1. Cleaned Data File (30 pts):
   - A .dat file exists, created during task.
   - Format is valid (whitespace separated, no commas).
   
2. QBlade Project File (30 pts):
   - falcon_design.wpa exists.
   - Created/modified during task.

3. Airfoil Content Verification (40 pts):
   - Project file contains the specific airfoil name or data.
   - Confirms the import was actually successful.

Pass Threshold: 70 points.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clean_and_import_airfoil_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Evaluate Criteria
    
    # Criterion 1: Cleaned Data File (30 pts)
    if result.get("clean_file_found") and result.get("clean_file_valid"):
        score += 30
        feedback_parts.append("Cleaned data file created successfully (+30)")
    elif result.get("clean_file_found"):
        score += 15
        feedback_parts.append("Data file created but may have formatting issues (+15)")
    else:
        feedback_parts.append("No valid cleaned data file found (0)")
        
    # Criterion 2: Project File Exists (30 pts)
    if result.get("project_exists"):
        score += 30
        feedback_parts.append("QBlade project file saved (+30)")
    else:
        feedback_parts.append("Project file 'falcon_design.wpa' not found (0)")
        
    # Criterion 3: Airfoil Content in Project (40 pts)
    # This proves the import worked and wasn't just an empty save
    if result.get("airfoil_found_in_project"):
        score += 40
        feedback_parts.append("Airfoil data verified inside project file (+40)")
    else:
        if result.get("project_exists"):
            feedback_parts.append("Project saved but airfoil data not detected inside (did import fail?) (0)")
        else:
            pass # Already penalized in step 2
            
    # Bonus/Penalty Check: App Running
    if not result.get("app_running"):
        feedback_parts.append("Warning: QBlade was closed before verification (no penalty)")
        
    # 3. Final Determination
    pass_threshold = 70
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }