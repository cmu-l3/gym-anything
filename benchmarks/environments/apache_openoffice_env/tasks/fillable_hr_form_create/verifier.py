#!/usr/bin/env python3
"""
Verifier for fillable_hr_form_create task.

Task: Create a form in OpenOffice Writer with interactive Form Controls.
Scoring:
- File creation and validity
- Presence of Form Controls (Text Boxes, Checkboxes, Date Fields)
- Branding presence

This verifier relies on the JSON output from export_result.sh which parses the ODT XML.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fillable_hr_form(traj, env_info, task_info):
    """
    Verify the OpenOffice Writer form creation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available"}

    # Load metadata requirements
    metadata = task_info.get('metadata', {})
    min_text = metadata.get('min_text_fields', 5)
    min_check = metadata.get('min_checkboxes', 3)
    min_date = metadata.get('min_date_fields', 1)

    # Fetch result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Initialize Score
    score = 0
    feedback = []
    
    # 1. File Existence & Validity (10 pts)
    if result.get('file_exists') and result.get('file_size', 0) > 2000:
        score += 10
        feedback.append("File created successfully")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or empty"}

    # 2. Form Definition Block Presence (20 pts)
    # This confirms they enabled forms and didn't just draw shapes
    if result.get('has_forms_xml'):
        score += 20
        feedback.append("Form definition structure found")
    else:
        feedback.append("No active form controls found (did you use the Form Controls toolbar?)")

    # 3. Text Fields (30 pts)
    # Require multiple fields (Name, Address, City, Phone, Email, SSN, Position, etc.)
    text_count = result.get('control_counts', {}).get('text_box', 0)
    if text_count >= min_text:
        score += 30
        feedback.append(f"Text fields: {text_count} (Pass)")
    elif text_count > 0:
        partial = int((text_count / min_text) * 30)
        score += partial
        feedback.append(f"Text fields: {text_count}/{min_text} (Partial)")
    else:
        feedback.append("Missing Text Box controls")

    # 4. Checkboxes (20 pts)
    # Require I-9, W-4, Handbook, etc.
    check_count = result.get('control_counts', {}).get('checkbox', 0)
    if check_count >= min_check:
        score += 20
        feedback.append(f"Checkboxes: {check_count} (Pass)")
    elif check_count > 0:
        partial = int((check_count / min_check) * 20)
        score += partial
        feedback.append(f"Checkboxes: {check_count}/{min_check} (Partial)")
    else:
        feedback.append("Missing Checkbox controls")

    # 5. Date Field (10 pts)
    # Accepts explicit <form:date> or <form:formatted-text> which is often used for dates
    date_count = result.get('control_counts', {}).get('date_field', 0)
    fmt_count = result.get('control_counts', {}).get('formatted_text', 0)
    total_date_likes = date_count + fmt_count
    
    if total_date_likes >= min_date:
        score += 10
        feedback.append("Date field found")
    else:
        feedback.append("Missing Date field")

    # 6. Branding / Content (10 pts)
    if result.get('company_name_found'):
        score += 10
        feedback.append("Company branding found")
    else:
        feedback.append("Company name missing in text")

    # Final Check
    passed = (score >= 70) and result.get('has_forms_xml')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }