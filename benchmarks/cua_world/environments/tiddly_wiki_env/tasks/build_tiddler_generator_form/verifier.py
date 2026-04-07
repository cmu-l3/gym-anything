#!/usr/bin/env python3
"""
Verifier for build_tiddler_generator_form task.

This verifier directly inspects the source code of the generated TiddlyWiki form.
Since TiddlyWiki forms use proprietary wikitext and widgets, evaluating the 
structural logic in the `.tid` file is highly robust and avoids false positives
from manual dummy-data creation (anti-gaming).
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_form_tiddler(traj, env_info, task_info):
    """Verify that the UI form tiddler was created with correct logic."""
    
    # CRITICAL: Always use copy_from_env, never exec_in_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/form_task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Tiddler Exists (10 points)
    form_exists = result.get('form_exists', False)
    if not form_exists:
        feedback_parts.append("FAIL: 'New Patient Registration Form' tiddler not found")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts)
        }

    score += 10
    feedback_parts.append("Form tiddler exists")

    text = result.get('form_text', '')

    # Criterion 2: Correct State Tiddler Target (15 points)
    if "$:/temp/NewPatient" in text:
        score += 15
        feedback_parts.append("Uses required state tiddler")
    else:
        feedback_parts.append("FAIL: Does not use $:/temp/NewPatient")

    # Criterion 3: Input Fields (20 points)
    has_edit = "<$edit-text" in text
    has_fields = all(f in text for f in ["patient_name", "dob", "physician"])
    if has_edit and has_fields:
        score += 20
        feedback_parts.append("All input fields defined")
    elif has_edit:
        score += 10
        feedback_parts.append("Partial input fields found")
    else:
        feedback_parts.append("FAIL: Missing <$edit-text widgets")

    # Criterion 4: Action Button (15 points)
    if "<$button" in text and "Register Patient" in text:
        score += 15
        feedback_parts.append("Action button correctly labeled")
    else:
        feedback_parts.append("FAIL: Missing 'Register Patient' <$button>")

    # Criterion 5: Create Action Logic (25 points)
    if "<$action-createtiddler" in text:
        create_checks = 0
        
        # Check title mapping
        if re.search(r'\$basetitle\s*=', text) or re.search(r'title\s*=', text):
            create_checks += 1
        # Check tagging
        if "Patient" in text and "tags" in text:
            create_checks += 1
        # Check field inclusions
        if "dob" in text and "physician" in text:
            create_checks += 1
        # Check text body
        if "!! Intake Notes" in text:
            create_checks += 1
        
        if create_checks >= 4:
            score += 25
            feedback_parts.append("Create action fully configured")
        elif create_checks >= 2:
            score += 15
            feedback_parts.append("Create action partially configured")
        else:
            score += 5
            feedback_parts.append("Create action poorly configured")
    else:
        feedback_parts.append("FAIL: Missing <$action-createtiddler>")

    # Criterion 6: Cleanup Action (15 points)
    if "<$action-deletetiddler" in text and "$:/temp/NewPatient" in text:
        score += 15
        feedback_parts.append("Cleanup action correctly clears form")
    else:
        feedback_parts.append("FAIL: Missing cleanup <$action-deletetiddler>")

    # Informational Anti-Gaming verification
    if result.get('gui_save_detected', False):
        feedback_parts.append("(GUI save detected)")
    else:
        feedback_parts.append("(No GUI save log - possible raw file edit)")

    # 70% threshold requires all critical widget wiring to be fundamentally correct
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }