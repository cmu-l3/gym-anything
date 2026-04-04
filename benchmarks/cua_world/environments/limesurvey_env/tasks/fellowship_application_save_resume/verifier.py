#!/usr/bin/env python3
"""
Verifier for fellowship_application_save_resume@1

Checks:
1. Survey exists with correct title.
2. "Save and resume" is enabled.
3. "Research Proposal" question exists (File upload type).
4. Question attributes: allowed_filetypes=pdf, max_filesize=5120, max_num_of_files=3.
5. Email template subject is customized correctly.
"""

import json
import os
import tempfile

def verify_fellowship_application(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', '2026 Doctoral Research Fellowship')
    expected_subject = metadata.get('expected_email_subject', 'Fellowship Application Progress Saved - Do Not Delete')
    expected_code = metadata.get('expected_question_code', 'proposal')

    # Copy result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Survey Existence (10 pts)
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey '2026 Doctoral Research Fellowship' not found."
        }
    
    title = result.get('title', '')
    if expected_title.lower() in title.lower():
        score += 10
        feedback_parts.append("Survey created")
    else:
        feedback_parts.append(f"Survey title mismatch: '{title}'")

    # 2. Save Enabled (25 pts)
    # LimeSurvey stores 'Y' for Yes, 'N' for No
    allow_save = result.get('allow_save', 'N')
    if allow_save == 'Y':
        score += 25
        feedback_parts.append("Save & Resume enabled")
    else:
        feedback_parts.append("Save & Resume NOT enabled")

    # 3. Question Type (15 pts)
    # File upload type code is '|' (pipe) or sometimes displayed as 'File upload' depending on query mapping
    # The raw DB type for file upload is usually '|'
    q_type = result.get('question_type', '')
    q_found = result.get('question_found')
    
    if q_found and q_type == '|':
        score += 15
        feedback_parts.append("File upload question found")
    elif q_found:
        feedback_parts.append(f"Question found but wrong type (got '{q_type}', expected File Upload '|')")
    else:
        feedback_parts.append("Question 'Research Proposal' not found")

    # 4. Attributes (15 + 10 + 10 = 35 pts)
    # Filetypes (15)
    ftypes = result.get('attr_filetypes', '').lower()
    if 'pdf' in ftypes and 'doc' not in ftypes and 'jpg' not in ftypes:
         # Strict check: should only be pdf
         if ftypes.strip() == 'pdf':
             score += 15
             feedback_parts.append("Filetypes restricted to PDF")
         else:
             score += 10 # Partial if pdf included but maybe others
             feedback_parts.append(f"Filetypes includes PDF but maybe others: {ftypes}")
    else:
         feedback_parts.append(f"Filetypes incorrect: {ftypes}")

    # Max Size (10)
    max_size = str(result.get('attr_maxsize', ''))
    if max_size == '5120':
        score += 10
        feedback_parts.append("Max size 5MB")
    else:
        feedback_parts.append(f"Max size incorrect: {max_size} KB")

    # Max Files (10)
    max_num = str(result.get('attr_maxnum', ''))
    if max_num == '3':
        score += 10
        feedback_parts.append("Max files 3")
    else:
        feedback_parts.append(f"Max files incorrect: {max_num}")

    # 5. Email Subject (15 pts)
    email_subj = result.get('email_subject', '')
    if expected_subject.strip().lower() == email_subj.strip().lower():
        score += 15
        feedback_parts.append("Email template customized")
    else:
        feedback_parts.append(f"Email subject mismatch. Expected '{expected_subject}', got '{email_subj}'")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }