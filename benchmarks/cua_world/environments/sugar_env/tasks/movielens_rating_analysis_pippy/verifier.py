#!/usr/bin/env python3
import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_movielens_rating_analysis(traj, env_info, task_info):
    """
    Verifies that the agent correctly processed the MovieLens 100k dataset.
    Includes a dynamic execution check to prevent hardcoding of answers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Python Script presence (10 pts)
    if result.get("script_exists"):
        score += 10
        feedback.append("Python script saved")
    else:
        feedback.append("Python script not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check Outputs generation (10 pts)
    txt_exists = result.get("txt_exists", False)
    html_exists = result.get("html_exists", False)
    
    if txt_exists and html_exists:
        score += 10
        feedback.append("Both output files created")
    elif txt_exists or html_exists:
        score += 5
        feedback.append("Only one output file created")
    else:
        feedback.append("Output files not found")
        
    # 3. Static Content Check: TXT (20 pts)
    txt_content = result.get("txt_content", "")
    has_avg_txt = bool(re.search(r'3\.5[234]', txt_content))
    has_count_txt = bool(re.search(r'21201', txt_content))
    
    if has_avg_txt and has_count_txt:
        score += 20
        feedback.append("Correct values in TXT")
    elif has_avg_txt or has_count_txt:
        score += 10
        feedback.append("Partial correct values in TXT")
        
    # 4. Static Content Check: HTML (20 pts)
    html_content = result.get("html_content", "")
    has_html_tags = bool(re.search(r'<html|<body|<p|<div|<h[1-6]', html_content, re.IGNORECASE))
    has_avg_html = bool(re.search(r'3\.5[234]', html_content))
    has_count_html = bool(re.search(r'21201', html_content))
    
    if has_html_tags and has_avg_html and has_count_html:
        score += 20
        feedback.append("Valid HTML with correct values")
    elif has_html_tags and (has_avg_html or has_count_html):
        score += 10
        feedback.append("Valid HTML with partial correct values")
        
    # 5. Dynamic Anti-Gaming Check (40 pts)
    dynamic_success = False
    if result.get("dynamic_run_success"):
        dyn_txt = result.get("dynamic_txt_content", "")
        
        # Synthetic data expected metrics: average = 2.80, 5-star count = 3
        dyn_txt_avg = bool(re.search(r'2\.80?', dyn_txt))
        dyn_txt_count = bool(re.search(r'(?<!\.)\b3\b(?!\.)', dyn_txt))
        
        if dyn_txt_avg and dyn_txt_count:
            score += 40
            dynamic_success = True
            feedback.append("Dynamic anti-gaming test PASSED")
        else:
            feedback.append("Dynamic test FAILED (script may be hardcoded or contains algorithmic errors)")
            
    passed = score >= 70 and dynamic_success
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback),
        "subscores": {
            "dynamic_passed": dynamic_success,
            "html_valid": has_html_tags
        }
    }