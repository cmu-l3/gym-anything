#!/usr/bin/env python3
"""
Verifier for iFixit Repair Checklist Creation task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ifixit_checklist(traj, env_info, task_info):
    """
    Verify the created checklist for iPhone 13 battery replacement.
    
    Criteria:
    1. File exists and was created during task (10 pts)
    2. Browser history shows visit to correct iFixit guide (20 pts)
    3. Content: Includes Difficulty and Time estimates (20 pts)
    4. Content: Includes critical tools (Pentalobe, Tri-point) (30 pts)
    5. Content: Includes safety warning (20 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load result
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
    
    # 1. File Existence (10 pts)
    if result.get("file_exists") and result.get("created_during_task"):
        score += 10
        feedback_parts.append("Checklist file created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Checklist file not found or not created during task."}
        
    # 2. History Check (20 pts)
    if result.get("visited_target_guide"):
        score += 20
        feedback_parts.append("Correct iFixit guide visited.")
    elif result.get("visited_ifixit"):
        score += 10
        feedback_parts.append("Visited iFixit, but maybe not the specific target guide url.")
    else:
        feedback_parts.append("No record of visiting iFixit.")

    content = result.get("file_content", "").lower()
    
    # 3. Metadata Extraction (20 pts)
    # iFixit usually lists "Moderate" and "1-3 hours" (or similar)
    has_difficulty = "moderate" in content
    has_time = "hour" in content or "hr" in content or "minute" in content
    
    if has_difficulty and has_time:
        score += 20
        feedback_parts.append("Extracted Difficulty and Time estimates.")
    elif has_difficulty or has_time:
        score += 10
        feedback_parts.append("Partially extracted metadata.")
    else:
        feedback_parts.append("Missing Difficulty/Time estimates.")
        
    # 4. Critical Tools (30 pts)
    # Critical tools for iPhone: Pentalobe, Tri-point (Y000), Spudger, Suction
    tools_found = 0
    critical_tools = ["pentalobe", "tri-point", "suction", "spudger"]
    # Some guides say "Y000" instead of tri-point, accept that
    if "y000" in content:
        content += " tri-point" 
        
    for tool in critical_tools:
        if tool in content:
            tools_found += 1
            
    if tools_found >= 3:
        score += 30
        feedback_parts.append(f"Found {tools_found}/4 critical tools.")
    elif tools_found > 0:
        score += 15
        feedback_parts.append(f"Found only {tools_found}/4 critical tools.")
    else:
        feedback_parts.append("No critical tools listed.")
        
    # 5. Safety Warning (20 pts)
    # Keywords: fire, puncture, swollen, explode
    safety_keywords = ["fire", "puncture", "swollen", "explode", "thermal", "leak", "discharge"]
    has_safety = any(k in content for k in safety_keywords)
    
    if has_safety:
        score += 20
        feedback_parts.append("Safety warning note included.")
    else:
        feedback_parts.append("Missing battery safety warning.")
        
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }