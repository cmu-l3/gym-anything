#!/usr/bin/env python3
"""
Verifier for create_form task (OpenMRS/Bahmni).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_form(traj, env_info, task_info):
    """
    Verify that the clinical form was created correctly in OpenMRS.
    
    Criteria:
    1. Form exists with exact name "COVID-19 Screening Form" (25 pts)
    2. Version is "1.0" (15 pts)
    3. Description contains keywords "covid", "symptom", "exposure" (20 pts)
    4. Form is Published (15 pts)
    5. Form was created AFTER task start time (Anti-gaming) (15 pts)
    6. Browser/Window evidence of Admin UI interaction (10 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    form_found = result.get('form_found', False)
    form_data = result.get('form_data', {})
    
    # 1. Form Existence (25 pts)
    if form_found:
        name = form_data.get('name', '')
        if name == "COVID-19 Screening Form":
            score += 25
            feedback_parts.append("Form created with correct name")
        else:
            score += 10 # Partial credit for partial match found by export script
            feedback_parts.append(f"Form created but name mismatch ('{name}')")
    else:
        feedback_parts.append("Form not found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Form 'COVID-19 Screening Form' was not found in OpenMRS."
        }

    # 2. Version Check (15 pts)
    version = form_data.get('version', '')
    if version == "1.0":
        score += 15
        feedback_parts.append("Correct version (1.0)")
    else:
        feedback_parts.append(f"Incorrect version: expected 1.0, got '{version}'")

    # 3. Description Check (20 pts)
    description = form_data.get('description', '').lower()
    keywords = ["covid", "symptom", "exposure"]
    found_keywords = [k for k in keywords if k in description]
    
    if len(found_keywords) == 3:
        score += 20
        feedback_parts.append("Description contains all required keywords")
    elif len(found_keywords) > 0:
        partial_score = int(20 * (len(found_keywords) / 3))
        score += partial_score
        feedback_parts.append(f"Description missing some keywords (found: {found_keywords})")
    else:
        feedback_parts.append("Description missing required keywords")

    # 4. Published Status (15 pts)
    published = form_data.get('published', False)
    if published:
        score += 15
        feedback_parts.append("Form is published")
    else:
        feedback_parts.append("Form is NOT published")

    # 5. Anti-gaming / Timestamp Check (15 pts)
    # The form must have been created *during* the task
    is_newly_created = result.get('is_newly_created', False)
    if is_newly_created:
        score += 15
        feedback_parts.append("Form created during task session")
    else:
        feedback_parts.append("Form creation timestamp predates task start (Anti-gaming fail)")

    # 6. Window Title / Admin Evidence (10 pts)
    # Check if they actually went to the admin page or just managed it via API (unlikely for agent, but good proxy for navigation)
    window_title = result.get('window_title', '')
    if any(x in window_title.lower() for x in ['openmrs', 'admin', 'form']):
        score += 10
        feedback_parts.append("Browser navigation verified")
    else:
        # If they succeeded in creating the form, they likely navigated, so give partial credit
        # if the form is newly created
        if is_newly_created:
            score += 5
            feedback_parts.append("Browser navigation inferred from success")
        else:
            feedback_parts.append("No evidence of Admin page navigation")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }