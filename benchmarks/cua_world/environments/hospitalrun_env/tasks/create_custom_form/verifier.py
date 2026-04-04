#!/usr/bin/env python3
"""Verifier for create_custom_form task.

Verifies:
1. Custom form document exists in CouchDB.
2. Form name is 'Fall Risk Assessment'.
3. Form type is 'Visit'.
4. All 5 required fields (ageGroup, fallHistory, mobilityStatus, cognitiveImpairment, assessmentNotes) exist.
5. Field properties (label, type, select options) match requirements.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_form(traj, env_info, task_info):
    """
    Verify that the 'Fall Risk Assessment' custom form was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_fields = metadata.get('fields', [])

    # Load result
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
    
    # 1. Check if document exists (15 points)
    form_doc = result.get('form_doc', {})
    if not form_doc or form_doc == {}:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Custom form 'Fall Risk Assessment' not found in database."
        }
    
    score += 15
    feedback_parts.append("Form document created")

    # 2. Check form Type (10 points)
    # HospitalRun might store it as 'visit' or 'Visit'
    form_type = form_doc.get('formType', '').lower()
    if form_type == 'visit':
        score += 10
        feedback_parts.append("Form type correct")
    else:
        feedback_parts.append(f"Incorrect form type: expected 'Visit', got '{form_doc.get('formType')}'")

    # 3. Check columns/fields structure (10 points for having fields)
    columns = form_doc.get('data', {}).get('columns', []) # Sometimes wrapped in 'data'
    if not columns:
        columns = form_doc.get('columns', []) # Or at root
    
    if len(columns) >= 5:
        score += 10
        feedback_parts.append(f"Found {len(columns)} fields")
    else:
        feedback_parts.append(f"Insufficient fields: found {len(columns)}, expected 5+")

    # 4. Check specific fields (55 points total distributed)
    # Helper to find column by property
    def find_col(prop):
        for col in columns:
            if col.get('property') == prop:
                return col
        return None

    # Field 1: ageGroup (Text) - 10 pts
    f1 = find_col('ageGroup')
    if f1:
        if f1.get('label') == 'Age Group' and f1.get('type') == 'text':
            score += 10
            feedback_parts.append("ageGroup correct")
        else:
            score += 5
            feedback_parts.append("ageGroup properties mismatch")
    else:
        feedback_parts.append("ageGroup missing")

    # Field 2: fallHistory (Select) - 15 pts
    f2 = find_col('fallHistory')
    if f2:
        if f2.get('label') == 'Fall History' and f2.get('type') == 'select':
            opts = f2.get('options', '').split(',')
            # Normalize options for comparison (strip whitespace)
            opts = [o.strip() for o in opts]
            expected_opts = ["None", "One fall in past 6 months", "Multiple falls"]
            if all(e in opts for e in expected_opts):
                score += 15
                feedback_parts.append("fallHistory correct")
            else:
                score += 7
                feedback_parts.append("fallHistory options mismatch")
        else:
            score += 5
            feedback_parts.append("fallHistory type/label mismatch")
    else:
        feedback_parts.append("fallHistory missing")

    # Field 3: mobilityStatus (Select) - 15 pts
    f3 = find_col('mobilityStatus')
    if f3:
        if f3.get('label') == 'Mobility Status' and f3.get('type') == 'select':
            opts = f3.get('options', '').split(',')
            opts = [o.strip() for o in opts]
            expected_opts = ["Independent", "Uses assistive device", "Requires assistance"]
            if all(e in opts for e in expected_opts):
                score += 15
                feedback_parts.append("mobilityStatus correct")
            else:
                score += 7
                feedback_parts.append("mobilityStatus options mismatch")
        else:
            score += 5
            feedback_parts.append("mobilityStatus type/label mismatch")
    else:
        feedback_parts.append("mobilityStatus missing")

    # Field 4: cognitiveImpairment (Checkbox) - 10 pts
    f4 = find_col('cognitiveImpairment')
    if f4:
        if f4.get('label') == 'Cognitive Impairment' and f4.get('type') == 'checkbox':
            score += 10
            feedback_parts.append("cognitiveImpairment correct")
        else:
            score += 5
            feedback_parts.append("cognitiveImpairment properties mismatch")
    else:
        feedback_parts.append("cognitiveImpairment missing")

    # Field 5: assessmentNotes (Text Area) - 10 pts
    f5 = find_col('assessmentNotes')
    if f5:
        # Accept 'textarea' or 'text area' or 'long text' depending on internal representation
        ftype = f5.get('type', '').lower()
        if f5.get('label') == 'Assessment Notes' and ('text' in ftype and 'area' in ftype):
            score += 10
            feedback_parts.append("assessmentNotes correct")
        elif f5.get('label') == 'Assessment Notes' and ftype == 'textarea':
             score += 10
             feedback_parts.append("assessmentNotes correct")
        else:
            score += 5
            feedback_parts.append(f"assessmentNotes type mismatch ({ftype})")
    else:
        feedback_parts.append("assessmentNotes missing")
        
    # Check VLM Evidence (5 points - simple check if result exists implies file created implies app running)
    if result.get('app_running'):
        score += 5
    
    # Final verdict
    passed = score >= 60 and (form_doc is not None)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }