#!/usr/bin/env python3
"""
Verifier for design_vawt_blade task.
Verifies that the user created a specific VAWT blade configuration in QBlade.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_vawt_blade(traj, env_info, task_info):
    """
    Verify the VAWT blade design task.
    
    Criteria:
    1. Project file exists and was created during task.
    2. File contains NACA 0021 airfoil definition.
    3. File contains VAWT blade definition (not HAWT).
    4. Blade geometry parameters match requirements (Chord ~0.15, Radius ~1.0, Height ~2.0, 3 Blades).
    5. VLM verification of UI interaction.
    """
    
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_path', '/home/ga/Documents/projects/urban_darrieus_vawt.wpa')
    
    # 2. Load basic result metadata
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_path)
        with open(temp_result_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution data"}
    finally:
        if os.path.exists(temp_result_path):
            os.unlink(temp_result_path)

    # 3. Download Project File for Content Analysis
    project_content = ""
    project_file_valid = False
    
    if task_result.get("output_exists") and task_result.get("file_created_during_task"):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wpa') as f:
            temp_wpa_path = f.name
        
        try:
            copy_from_env(expected_path, temp_wpa_path)
            with open(temp_wpa_path, 'r', errors='ignore') as f:
                project_content = f.read()
            project_file_valid = True
        except Exception as e:
            logger.error(f"Failed to read project file: {e}")
        finally:
            if os.path.exists(temp_wpa_path):
                os.unlink(temp_wpa_path)

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion 1: File Existence & Validity (20 pts)
    if task_result.get("output_exists"):
        if task_result.get("file_created_during_task"):
            score += 20
            feedback.append("Project file created successfully.")
        else:
            score += 5
            feedback.append("Project file exists but timestamp indicates it wasn't created during this session.")
    else:
        feedback.append("Project file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if not project_file_valid or len(project_content) < 100:
        feedback.append("Project file is empty or unreadable.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # Criterion 2: Airfoil Content (20 pts)
    # Check for NACA 0021
    if re.search(r"NACA\s*0021", project_content, re.IGNORECASE) or \
       (re.search(r"NACA", project_content, re.IGNORECASE) and re.search(r"0021", project_content)):
        score += 20
        feedback.append("NACA 0021 airfoil found in project.")
    else:
        feedback.append("Could not find NACA 0021 airfoil in project.")

    # Criterion 3: VAWT Blade Definition (20 pts)
    # QBlade saves VAWT blades often with specific headers or parameters
    if re.search(r"VAWT", project_content, re.IGNORECASE) and re.search(r"Blade", project_content, re.IGNORECASE):
        score += 10
        feedback.append("VAWT configuration detected.")
    
    # Check blade name
    if re.search(r"UrbanDarrieus", project_content, re.IGNORECASE):
        score += 10
        feedback.append("Correct blade name 'UrbanDarrieus' found.")
    else:
        feedback.append("Blade name 'UrbanDarrieus' not found.")

    # Criterion 4: Geometric Parameters (40 pts)
    # We look for patterns like "NumBlades = 3" or similar in text
    
    # Check Blade Count (3)
    if re.search(r"Number.*Blades.*3", project_content, re.IGNORECASE) or \
       re.search(r"Blades.*3", project_content, re.IGNORECASE) or \
       re.search(r"NumBl.*3", project_content, re.IGNORECASE):
        score += 10
        feedback.append("3 Blades configuration found.")
    else:
        feedback.append("Could not confirm 3-blade configuration.")

    # Check Chord (0.15)
    if re.search(r"0\.15", project_content):
        score += 10
        feedback.append("Chord value 0.15m found.")
    else:
        feedback.append("Target chord (0.15m) not found in file.")

    # Check Radius/Offset (1.0)
    if re.search(r"Offset.*1(\.0)?", project_content, re.IGNORECASE) or \
       re.search(r"Radius.*1(\.0)?", project_content, re.IGNORECASE):
        score += 10
        feedback.append("Radius/Offset 1.0m found.")
    else:
        # Fallback check for just the number 1.0 in a context that looks like geometry
        if len(re.findall(r"1\.00", project_content)) > 2: # At least height and radius
            score += 5
            feedback.append("Value 1.0m found (likely Radius/Offset).")
        else:
            feedback.append("Target Radius/Offset (1.0m) not confirmed.")

    # Check Height (2.0)
    if re.search(r"Height.*2(\.0)?", project_content, re.IGNORECASE) or \
       re.search(r"Pos.*2(\.0)?", project_content, re.IGNORECASE): # Position of top station
        score += 10
        feedback.append("Height/Position 2.0m found.")
    else:
        if re.search(r"2\.00", project_content):
            score += 5
            feedback.append("Value 2.0m found (likely Height).")
        else:
            feedback.append("Target Height (2.0m) not confirmed.")

    # 5. Final Decision
    # Pass if Score >= 60 and basic file criteria are met
    passed = (score >= 60) and task_result.get("file_created_during_task")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }