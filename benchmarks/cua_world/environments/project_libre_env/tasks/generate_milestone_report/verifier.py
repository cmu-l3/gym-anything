#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from pdfminer.high_level import extract_text

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_milestone_report(traj, env_info, task_info):
    """
    Verifies that the agent created a PDF report containing ONLY milestones.
    
    Verification Logic:
    1. Check file existence and creation time.
    2. Extract text from PDF.
    3. Positive Check: Ensure milestone names are present.
    4. Negative Check: Ensure standard task names are ABSENT (proof of filtering).
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    required_text = metadata.get('required_text', ["Design Review Milestone", "Project Completion Milestone"])
    forbidden_text = metadata.get('forbidden_text', ["Requirements Gathering", "Backend API Development"])

    # Retrieve result JSON
    with tempfile.NamedTemporaryFile(suffix=".json") as f_json:
        try:
            copy_from_env("/tmp/task_result.json", f_json.name)
            f_json.seek(0)
            result = json.load(f_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # Basic Checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "The file 'milestones.pdf' was not found in '~/Projects/'."}
        
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "A file exists, but it was not created during the current task session."}

    # Retrieve PDF content
    pdf_text = ""
    with tempfile.NamedTemporaryFile(suffix=".pdf") as f_pdf:
        try:
            copy_from_env(result["output_path"], f_pdf.name)
            # Extract text using pdfminer
            try:
                pdf_text = extract_text(f_pdf.name)
            except Exception as e:
                 return {"passed": False, "score": 20, "feedback": f"File exists but is not a valid PDF or could not be parsed: {str(e)}"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve PDF file: {str(e)}"}

    # Content Analysis
    score = 20 # Base score for creating valid PDF
    feedback = ["PDF created successfully."]
    
    # 1. Positive Verification (Milestones present)
    milestones_found = 0
    for text in required_text:
        if text.lower() in pdf_text.lower():
            milestones_found += 1
        else:
            feedback.append(f"Missing expected milestone: '{text}'")
    
    if milestones_found == len(required_text):
        score += 30
        feedback.append("All expected milestones found.")
    elif milestones_found > 0:
        score += 15
        feedback.append("Some milestones found.")
    else:
        feedback.append("No milestones found in the document.")

    # 2. Negative Verification (Standard tasks absent)
    # This proves the filter was applied correctly
    standard_tasks_found = 0
    for text in forbidden_text:
        if text.lower() in pdf_text.lower():
            standard_tasks_found += 1
            feedback.append(f"Found non-milestone task: '{text}' (Filter failed)")
    
    if standard_tasks_found == 0:
        score += 50
        feedback.append("Filter verified: No standard tasks found.")
    else:
        feedback.append("Filter check failed: The report contains standard tasks.")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }