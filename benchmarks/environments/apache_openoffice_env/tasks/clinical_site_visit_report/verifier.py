#!/usr/bin/env python3
"""
Verifier for clinical_site_visit_report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clinical_site_visit_report(traj, env_info, task_info):
    """
    Verify the Clinical Site Visit Report ODT file.
    
    Scoring Criteria:
    1. File Creation (10 pts)
    2. Headers/Footers (Protocol ZN-994, Page #) (10 pts)
    3. Heading Styles (Heading 1 usage) (20 pts)
    4. Enrollment Logic (Active = 9) (35 pts)
    5. Action Items & Conditional Formatting (25 pts)
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

    # Parse inputs
    analysis = result.get('analysis', {})
    file_exists = result.get('file_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    score = 0
    feedback = []
    
    # 1. File Creation (10 pts)
    if file_exists and created_during:
        score += 10
        feedback.append("File created successfully.")
    elif file_exists:
        score += 5
        feedback.append("File exists but timestamp is suspicious.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Headers/Footers (10 pts)
    if analysis.get("has_protocol_header", False):
        score += 5
        feedback.append("Protocol/Site header found.")
    else:
        feedback.append("Missing Protocol ZN-994/Site 142 in header/body.")

    if analysis.get("page_numbers_found", False):
        score += 5
        feedback.append("Page numbers found.")
    else:
        feedback.append("Missing page numbers.")

    # 3. Heading Styles (20 pts)
    h1_count = analysis.get("heading1_count", 0)
    if h1_count >= 4:
        score += 20
        feedback.append(f"Heading 1 styles applied correctly ({h1_count} sections).")
    elif h1_count > 0:
        score += 10
        feedback.append(f"Partial Heading 1 styles found ({h1_count}/4).")
    else:
        feedback.append("No 'Heading 1' styles detected.")

    # 4. Enrollment Logic (35 pts)
    # The crucial part is the calculation: Active = 9
    if analysis.get("calculated_active_correct", False):
        score += 35
        feedback.append("Enrollment logic correct (Active = 9).")
    else:
        feedback.append("Enrollment logic incorrect or missing (Active count of 9 not found).")

    # 5. Action Items & Formatting (25 pts)
    if analysis.get("has_action_items_table", False):
        score += 10
        feedback.append("Action Items table found.")
        
        if analysis.get("conditional_formatting_found", False):
            score += 15
            feedback.append("Conditional formatting for 'Open' items detected (Red/Highlight).")
        else:
            feedback.append("Conditional formatting for 'Open' items missing.")
    else:
        feedback.append("Action Items table missing.")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }