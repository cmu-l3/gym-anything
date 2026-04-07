#!/usr/bin/env python3
"""
Verifier for print_stylesheet_compliance_audit@1

This verifies that the agent:
1. Created a PDF file at the expected location.
2. The file was created during the task window.
3. The PDF contains the correct article content.
4. CRITICAL: The PDF does NOT contain sidebar navigation elements (Donate, Current events),
   proving that the print stylesheet was correctly applied and the agent didn't just 
   print "As shown on screen" or take a screenshot.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_stylesheet_compliance_audit(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result from container
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

    # 3. Analyze Results
    score = 0
    feedback = []
    
    file_exists = result.get("file_exists", False)
    created_during_task = result.get("created_during_task", False)
    file_size = result.get("file_size", 0)
    pdf_analysis = result.get("pdf_analysis", {})
    
    # Criterion 1: File Existence (10 pts)
    if file_exists:
        score += 10
        feedback.append("PDF file found on Desktop.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output PDF not found on Desktop."}

    # Criterion 2: Timestamp (10 pts)
    if created_during_task:
        score += 10
        feedback.append("File was created during the task.")
    else:
        feedback.append("File timestamp is invalid (created before task start?).")

    # Criterion 3: File Validity & Size (10 pts)
    if pdf_analysis.get("is_valid_pdf", False) and file_size > 1000:
        score += 10
        feedback.append(f"File is a valid PDF ({file_size} bytes).")
    else:
        feedback.append("File is not a valid PDF or is empty.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # Criterion 4: Content Presence (30 pts)
    # The article text must be present
    if pdf_analysis.get("has_required_text", False):
        score += 30
        feedback.append("Main article content found.")
    else:
        feedback.append("Main article text missing from PDF.")

    # Criterion 5: Content Absence (The Compliance Check) (40 pts)
    # The sidebar elements MUST be missing.
    if not pdf_analysis.get("has_forbidden_text", True):
        score += 40
        feedback.append("Compliance Check Passed: Sidebar navigation is correctly hidden.")
    else:
        forbidden_found = pdf_analysis.get("found_forbidden_terms", [])
        feedback.append(f"Compliance Check Failed: Sidebar elements found in PDF ({', '.join(forbidden_found)}). Print stylesheet was not correctly applied.")

    # Final logic
    passed = score >= 80  # Requires clean PDF + content + timestamps
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }