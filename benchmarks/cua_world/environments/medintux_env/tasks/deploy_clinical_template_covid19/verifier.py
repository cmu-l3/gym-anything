#!/usr/bin/env python3
"""
Verifier for deploy_clinical_template_covid19 task.
"""

import json
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_clinical_template_covid19(traj, env_info, task_info):
    """
    Verify that the agent created the correct directory and HTML file with required clinical content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    import tempfile
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

    # Criteria weights
    score = 0
    feedback_parts = []
    
    # 1. File Existence & Location (40 pts)
    # 20 pts for file existing
    # 20 pts for correct directory structure
    if result.get("file_exists", False):
        score += 20
        feedback_parts.append("File created")
        
        if result.get("directory_correct", False):
            score += 20
            feedback_parts.append("Directory 'Protocoles_Urgence' correct")
        else:
            feedback_parts.append("File found but NOT in 'Protocoles_Urgence' folder")
            
        if not result.get("file_created_during_task", False):
            score = 0 # Anti-gaming: must be created now
            return {"passed": False, "score": 0, "feedback": "File existed before task start (anti-gaming)"}
    else:
        return {"passed": False, "score": 0, "feedback": "File 'Depistage_COVID19.html' not found"}

    # Decode content
    try:
        content_b64 = result.get("file_content_b64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception:
        content = ""
        feedback_parts.append("Could not read file content")

    # 2. Content Verification (50 pts)
    # Required strings from metadata
    metadata = task_info.get("metadata", {})
    required_strings = metadata.get("required_strings", [
        "PROTOCOLE DEPISTAGE RESPIRATOIRE",
        "Température",
        "Saturation O2",
        "Toux",
        "Dyspnée",
        "Anosmie"
    ])

    found_strings = 0
    missing_strings = []
    
    for s in required_strings:
        if s.lower() in content.lower():
            found_strings += 1
        else:
            missing_strings.append(s)
            
    # Calculate content score
    # We have 6 required strings. 50 points total. ~8.3 points per string.
    points_per_string = 50 / len(required_strings)
    content_score = int(found_strings * points_per_string)
    score += content_score
    
    if found_strings == len(required_strings):
        feedback_parts.append("All clinical fields present")
    else:
        feedback_parts.append(f"Missing fields: {', '.join(missing_strings)}")

    # 3. HTML Format (10 pts)
    if "<html>" in content.lower() or "<!doctype html>" in content.lower() or "<body>" in content.lower():
        score += 10
        feedback_parts.append("Valid HTML tags found")
    elif "<br>" in content.lower() or "<b>" in content.lower():
        score += 5
        feedback_parts.append("Basic HTML tags found")
    else:
        feedback_parts.append("No HTML tags found")

    # Pass threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }