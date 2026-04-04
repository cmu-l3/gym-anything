#!/usr/bin/env python3
"""
Verifier for Academic Domain Branching task.
Checks for correct use of ExpressionScript regex logic in LimeSurvey.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_academic_domain_branching(traj, env_info, task_info):
    """
    Verify the academic branching survey structure and logic.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    # Basic checks
    if not result.get('survey_found', False):
        return {"passed": False, "score": 0, "feedback": "Survey 'National Research Collaboration Study 2025' not found."}

    groups = result.get('groups', [])
    questions = result.get('questions', [])

    score = 0
    feedback = []
    
    # 1. Check Survey Structure (10 pts)
    # Expect 3 specific groups: Contact Info, Academic Track, Industry Track
    group_names = [g.get('name', '').lower() for g in groups]
    has_contact = any('contact' in n for n in group_names)
    has_academic = any('academic' in n for n in group_names)
    has_industry = any('industry' in n for n in group_names)
    
    if has_contact and has_academic and has_industry:
        score += 10
        feedback.append("Survey structure correct (3 groups found).")
    else:
        feedback.append(f"Survey structure incomplete. Found groups: {group_names}")

    # 2. Email Validation (20 pts)
    # Question 'email' should have a regex validation for '@'
    email_q = next((q for q in questions if q['code'].lower() == 'email'), None)
    if email_q:
        preg = email_q.get('preg', '')
        # Check for regexMatch function OR raw regex containing @
        if 'regexmatch' in preg.lower() or ('@' in preg and ('/' in preg or '#' in preg)):
            score += 20
            feedback.append("Email validation regex configured.")
        elif '@' in preg:
            # Partial credit for simple validation without full regex syntax if it looks like an attempt
            score += 10
            feedback.append("Email validation present but might lack strict regex syntax.")
        else:
            feedback.append(f"Email validation missing or incorrect (found: '{preg}').")
    else:
        feedback.append("Email question not found.")

    # 3. Academic Logic (35 pts)
    # Group Relevance must use regexMatch and target .edu
    acad_group = next((g for g in groups if 'academic' in g['name'].lower()), None)
    if acad_group:
        relevance = acad_group.get('relevance', '').lower()
        # Look for regexMatch AND .edu
        # Example: regexMatch('/\.edu$/i', email)
        if 'regexmatch' in relevance and '.edu' in relevance:
            score += 35
            feedback.append("Academic track logic correct (uses regexMatch for .edu).")
        elif '.edu' in relevance:
            # Partial credit if logic attempts .edu check but misses regexMatch (e.g. strpos)
            score += 15
            feedback.append("Academic track logic checks .edu but may not use regexMatch as requested.")
        else:
            feedback.append(f"Academic track logic incorrect (found: '{relevance}').")
    else:
        feedback.append("Academic group not found.")

    # 4. Industry Logic (35 pts)
    # Group Relevance must EXCLUDE .edu (using ! or not)
    ind_group = next((g for g in groups if 'industry' in g['name'].lower()), None)
    if ind_group:
        relevance = ind_group.get('relevance', '').lower()
        # Look for negation (!) AND .edu
        if '!' in relevance and '.edu' in relevance:
             score += 35
             feedback.append("Industry track logic correct (negation of .edu).")
        elif '!' in relevance and 'academic' in relevance:
             # Logic might say "!academic_group_shown" - technically valid if academic group handles the logic
             # But prompt asked for email logic.
             score += 20
             feedback.append("Industry track logic uses negation but relies on group dependency rather than email regex.")
        else:
             feedback.append(f"Industry track logic incorrect (found: '{relevance}').")
    else:
        feedback.append("Industry group not found.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }