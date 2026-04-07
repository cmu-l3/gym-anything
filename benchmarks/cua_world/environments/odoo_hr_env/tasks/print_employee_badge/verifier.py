#!/usr/bin/env python3
import json
import os
import tempfile
from pdfminer.high_level import extract_text

def verify_print_employee_badge(traj, env_info, task_info):
    """
    Verifies that the employee badge PDF was generated correctly.
    
    Criteria:
    1. /home/ga/badge.pdf exists (20 pts)
    2. File is a valid PDF (30 pts)
    3. Content contains "Anita Oliver" (40 pts)
    4. File was created during the task (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    score = 0
    feedback = []
    
    # Temp files
    local_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    local_pdf = tempfile.NamedTemporaryFile(delete=False, suffix=".pdf").name
    
    try:
        # Fetch JSON result
        try:
            copy_from_env("/tmp/task_result.json", local_json)
            with open(local_json, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
        
        # Check Existence
        if not result.get("file_exists", False):
            return {"passed": False, "score": 0, "feedback": "File /home/ga/badge.pdf not found."}
        
        score += 20
        feedback.append("File exists")
        
        # Check Freshness
        if result.get("is_fresh", False):
            score += 10
            feedback.append("File created during task")
        else:
            feedback.append("File is stale (created before task start)")
        
        # Fetch PDF file
        try:
            copy_from_env("/tmp/badge_artifact.pdf", local_pdf)
            
            # Check PDF Validity and Content
            try:
                text = extract_text(local_pdf)
                score += 30 # Valid PDF if extraction works
                feedback.append("Valid PDF format")
                
                if "Anita Oliver" in text:
                    score += 40
                    feedback.append("Correct employee name found in badge")
                else:
                    feedback.append("Employee name 'Anita Oliver' NOT found in PDF text")
                    
            except Exception as e:
                feedback.append(f"Invalid PDF or extract failed: {str(e)}")
                
        except Exception as e:
            feedback.append(f"Failed to retrieve PDF file: {e}")

    finally:
        if os.path.exists(local_json): os.unlink(local_json)
        if os.path.exists(local_pdf): os.unlink(local_pdf)
    
    passed = score >= 90  # Requires almost perfect execution
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }