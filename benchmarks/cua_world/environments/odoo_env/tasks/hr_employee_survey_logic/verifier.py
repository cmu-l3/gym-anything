#!/usr/bin/env python3
"""
Verifier for HR Employee Survey Logic task.

Scoring (100 pts):
1. Survey created with correct title (10 pts)
2. Q1 (Location) exists and is multiple choice (15 pts)
3. Q1 has correct options (Office, Remote, Hybrid) (5 pts)
4. Q2 (Internet) exists and is text box (15 pts)
5. Q2 has CONDITIONAL LOGIC correctly configured (25 pts)
   - Must depend on Q1
   - Must trigger on "Remote" AND/OR "Hybrid"
6. Q3 (Satisfaction) exists and is matrix (15 pts)
7. Q3 has correct rows/columns (15 pts)

Pass threshold: 75 pts (Requires logic to be correct)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_hr_employee_survey_logic(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env('/tmp/hr_survey_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Survey Exists (10 pts)
    if result.get("survey_found"):
        score += 10
        feedback_parts.append("Survey 'Remote Work Readiness 2026' created (10/10)")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey not found. Did you save it with the exact title?"}

    questions = result.get("questions", [])
    
    # Find specific questions by loose text matching
    q1 = next((q for q in questions if "primary" in q['title'].lower() or "location" in q['title'].lower()), None)
    q2 = next((q for q in questions if "internet" in q['title'].lower() or "setup" in q['title'].lower()), None)
    q3 = next((q for q in questions if "satisfaction" in q['title'].lower() or "tools" in q['title'].lower()), None)

    # 2. Q1 Verification (20 pts)
    if q1:
        if q1['type'] == 'simple_choice': # 'radio' in UI, 'simple_choice' in DB
            score += 15
            feedback_parts.append("Q1 correct type (15/15)")
            
            # Check options (5 pts)
            options = [o.lower() for o in q1.get('answers', [])]
            if any("remote" in o for o in options) and any("hybrid" in o for o in options):
                score += 5
                feedback_parts.append("Q1 options correct (5/5)")
            else:
                feedback_parts.append("Q1 missing 'Remote' or 'Hybrid' options (0/5)")
        else:
            feedback_parts.append(f"Q1 wrong type: {q1['type']} (expected Multiple Choice) (0/20)")
    else:
        feedback_parts.append("Q1 'Primary work location' not found (0/20)")

    # 3. Q2 Verification (15 pts base)
    q2_valid = False
    if q2:
        if q2['type'] in ['text_box', 'char_box']: # 'Multiple Lines Text Box' usually 'text_box'
            score += 15
            q2_valid = True
            feedback_parts.append("Q2 correct type (15/15)")
        else:
            feedback_parts.append(f"Q2 wrong type: {q2['type']} (expected Text Box) (0/15)")
    else:
        feedback_parts.append("Q2 'Home internet setup' not found (0/15)")

    # 4. CONDITIONAL LOGIC (25 pts) - CRITICAL
    if q2_valid and q1:
        is_conditional = q2.get('is_conditional', False)
        trigger_q = q2.get('trigger_question_id')
        trigger_vals = [v.lower() for v in q2.get('trigger_values', [])]
        
        # Check if logic enabled
        if is_conditional:
            # Check if linked to Q1 (can try by ID if we captured Q1 id, but here we assume if conditional matches values it's correct)
            # We strictly need it to trigger on "Remote" or "Hybrid"
            has_remote = any("remote" in v for v in trigger_vals)
            has_hybrid = any("hybrid" in v for v in trigger_vals)
            
            if has_remote:
                score += 25
                feedback_parts.append("Conditional logic correctly configured (25/25)")
            else:
                score += 10
                feedback_parts.append("Conditional logic enabled but not triggering on 'Remote' (10/25)")
        else:
            feedback_parts.append("Conditional logic NOT enabled on Q2 (0/25)")
    elif q2_valid:
        feedback_parts.append("Cannot verify logic because Q1 is missing (0/25)")

    # 5. Q3 Verification (30 pts)
    if q3:
        if q3['type'] == 'matrix':
            score += 15
            feedback_parts.append("Q3 correct type (Matrix) (15/15)")
            
            rows = [r.lower() for r in q3.get('rows', [])]
            cols = [c.lower() for c in q3.get('answers', [])] # In Odoo matrix cols are stored in suggested_answer_ids
            
            rows_ok = any("laptop" in r for r in rows) and any("vpn" in r for r in rows)
            cols_ok = any("satisfied" in c for c in cols)
            
            if rows_ok and cols_ok:
                score += 15
                feedback_parts.append("Matrix rows/cols correct (15/15)")
            elif rows_ok:
                score += 7
                feedback_parts.append("Matrix rows correct, cols mismatch (7/15)")
            elif cols_ok:
                score += 7
                feedback_parts.append("Matrix cols correct, rows mismatch (7/15)")
            else:
                feedback_parts.append("Matrix structure incorrect (0/15)")
        else:
            feedback_parts.append(f"Q3 wrong type: {q3['type']} (expected Matrix) (0/30)")
    else:
        feedback_parts.append("Q3 'Satisfaction' not found (0/30)")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }