#!/usr/bin/env python3
"""
Verifier for Insurance Claims Upload Task.

Verifies:
1. Survey exists and is active.
2. Question 'HAS_EVIDENCE' exists.
3. Question 'FORM_PDF' exists, is File Upload, PDF only, max 1 file.
4. Question 'DMG_PHOTOS' exists, is File Upload, JPG/PNG, max 5 files.
5. 'DMG_PHOTOS' has conditional logic linking it to 'HAS_EVIDENCE'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insurance_claims_upload(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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
    feedback = []

    # 1. Survey Structure (15 pts)
    if result.get('survey_found'):
        score += 10
        feedback.append("Survey found.")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey 'Auto Insurance Claim Portal 2025' not found."}

    if result.get('survey_active'):
        score += 5
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    questions = result.get('questions', {})

    # 2. HAS_EVIDENCE (10 pts)
    q_evidence = questions.get('HAS_EVIDENCE', {})
    if q_evidence.get('exists'):
        score += 10
        feedback.append("Question HAS_EVIDENCE created.")
    else:
        feedback.append("Question HAS_EVIDENCE missing.")

    # 3. FORM_PDF Configuration (35 pts)
    q_pdf = questions.get('FORM_PDF', {})
    if q_pdf.get('exists'):
        score += 5
        # Check Type (LimeSurvey file upload type is usually '|')
        if q_pdf.get('type') == '|':
            score += 5
        else:
            feedback.append(f"FORM_PDF wrong type: {q_pdf.get('type')}")
        
        attrs = q_pdf.get('attributes', {})
        
        # Filetypes
        ft = attrs.get('allowed_filetypes', '').lower()
        if 'pdf' in ft and 'doc' not in ft and 'jpg' not in ft:
            score += 15
            feedback.append("FORM_PDF restricted to PDF correctly.")
        else:
            feedback.append(f"FORM_PDF allowed types incorrect: {ft}")

        # Max files
        mf = str(attrs.get('max_num_of_files', '0'))
        if mf == '1':
            score += 10
            feedback.append("FORM_PDF max files set to 1.")
        else:
            feedback.append(f"FORM_PDF max files incorrect: {mf}")
    else:
        feedback.append("Question FORM_PDF missing.")

    # 4. DMG_PHOTOS Configuration (40 pts)
    q_photos = questions.get('DMG_PHOTOS', {})
    if q_photos.get('exists'):
        score += 5
        
        attrs = q_photos.get('attributes', {})
        
        # Filetypes
        ft = attrs.get('allowed_filetypes', '').lower()
        if ('jpg' in ft or 'jpeg' in ft) and 'png' in ft and 'pdf' not in ft:
            score += 15
            feedback.append("DMG_PHOTOS allowed types correct (images only).")
        else:
            feedback.append(f"DMG_PHOTOS allowed types incorrect: {ft}")

        # Max files
        mf = str(attrs.get('max_num_of_files', '0'))
        if mf == '5':
            score += 10
            feedback.append("DMG_PHOTOS max files set to 5.")
        else:
            feedback.append(f"DMG_PHOTOS max files incorrect: {mf}")

        # Conditional Logic
        # Relevance should reference HAS_EVIDENCE and "Y" or "A1" (depending on answer code used)
        relevance = q_photos.get('relevance', '')
        if 'HAS_EVIDENCE' in relevance and ('Y' in relevance or 'A1' in relevance or 'SQ001' in relevance):
            score += 10
            feedback.append("Conditional logic detected.")
        else:
            feedback.append(f"Conditional logic missing or incorrect: {relevance}")

    else:
        feedback.append("Question DMG_PHOTOS missing.")

    # Final check
    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }