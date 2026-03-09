#!/usr/bin/env python3
"""
Verifier for saas_pricing_matrix_logic task.

Criteria:
1. Survey 'SaaS Pricing Strategy 2026' exists.
2. Q1 (PREF) is List/Radio ('L') and contains an HTML table with specific pricing data ($29, $79).
3. Q2 (INTEG) is Multiple Choice ('M') and has 'No integrations needed' configured as exclusive.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_saas_pricing_matrix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata
    metadata = task_info.get('metadata', {})
    table_strings = metadata.get('table_strings', ["<table", "$29", "$79"])
    
    # Copy result
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
            
    score = 0
    feedback = []
    
    # 1. Survey Check
    if not result.get('survey_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey 'SaaS Pricing Strategy 2026' not found."
        }
    score += 10
    feedback.append("Survey found.")
    
    # 2. Q1 Checks (HTML Table)
    q1 = result.get('q1', {})
    if q1.get('found'):
        if q1.get('type') == 'L':
            score += 10
            feedback.append("Q1 correct type (List Radio).")
        else:
            feedback.append(f"Q1 wrong type: {q1.get('type')}")
            
        html_content = q1.get('html_content', '').lower()
        # Verify Table Tags
        if '<table' in html_content and '</table>' in html_content:
            score += 20
            feedback.append("HTML Table tags found in Q1.")
        else:
            feedback.append("No HTML <table> tags found in Q1 text.")
            
        # Verify Data
        data_found = True
        missing_data = []
        for s in table_strings:
            if s.lower() not in html_content:
                data_found = False
                missing_data.append(s)
        
        if data_found:
            score += 20
            feedback.append("All pricing data ($29, $79, etc) found in table.")
        else:
            feedback.append(f"Missing pricing data in table: {missing_data}")
    else:
        feedback.append("Q1 (PREF) not found.")

    # 3. Q2 Checks (Exclusive Option)
    q2 = result.get('q2', {})
    if q2.get('found'):
        if q2.get('type') == 'M':
            score += 10
            feedback.append("Q2 correct type (Multiple Choice).")
        else:
            feedback.append(f"Q2 wrong type: {q2.get('type')}")
            
        # Verify Exclusivity
        # The attribute value (exclusive_option) must match the code for the "No integrations" answer
        no_integ_code = q2.get('no_integ_code', '').strip()
        exclusive_attr = q2.get('exclusive_attr_value', '').strip()
        
        if no_integ_code and exclusive_attr:
            # Check exact match or if attr contains the code (sometimes space separated)
            if no_integ_code == exclusive_attr or no_integ_code in exclusive_attr.split():
                score += 30
                feedback.append(f"Exclusive option correctly configured for '{no_integ_code}'.")
            else:
                feedback.append(f"Exclusive attribute mismatch. Attr: '{exclusive_attr}', Code: '{no_integ_code}'.")
        else:
            feedback.append("Exclusive option not configured or 'No integrations' answer not found.")
    else:
        feedback.append("Q2 (INTEG) not found.")
        
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }