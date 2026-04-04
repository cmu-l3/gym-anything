#!/usr/bin/env python3
"""
Verifier for spane_psychometric_scoring_logic task.

Checks:
1. Survey settings (Group-by-group format is critical for logic variables).
2. Structure (2 Arrays, correct subquestions).
3. Logic (Equation questions with valid sum/subtraction syntax).
4. Display (Piping syntax).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spane_psychometric_scoring_logic(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ---------------------------------------------------------
    # SCORING LOGIC
    # ---------------------------------------------------------
    score = 0
    feedback = []

    # 1. SURVEY EXISTENCE & SETTINGS (10 pts)
    if not result.get('survey_found'):
        return {"passed": False, "score": 0, "feedback": "Survey 'Well-being Study 2025' not found."}

    # Format must be 'G' (Group by group) for logic to calculate before display page
    # LimeSurvey stores format as 'G' (Group), 'S' (Question), 'A' (All in one)
    fmt = result.get('survey_format', '').upper()
    if fmt == 'G':
        score += 10
        feedback.append("Survey format is correctly 'Group by group' (10/10)")
    else:
        feedback.append(f"Survey format is '{fmt}' instead of 'Group by group'. Logic variables may not populate correctly. (0/10)")

    questions = result.get('questions', [])
    answers = result.get('answers', [])

    # Helper to find question by title (code)
    def get_q(code):
        return next((q for q in questions if q['title'].upper() == code.upper()), None)
    
    # Helper to find subquestions
    def get_subqs(parent_id):
        return [q for q in questions if q['parent_qid'] == parent_id]

    # 2. ARRAY STRUCTURE (30 pts)
    # Check SPANEP and SPANEN
    arrays_ok = True
    for code, name in [('SPANEP', 'Positive'), ('SPANEN', 'Negative')]:
        q = get_q(code)
        if not q:
            feedback.append(f"Question '{code}' not found (0/15)")
            arrays_ok = False
            continue
        
        # Check type (F = Array)
        if q['type'] != 'F':
            feedback.append(f"'{code}' is type '{q['type']}', expected 'F' (Array) (0/5)")
            arrays_ok = False
        else:
            # Check subquestions
            subs = get_subqs(q['qid'])
            if len(subs) >= 6:
                score += 15
                feedback.append(f"'{code}' has {len(subs)} items (15/15)")
            else:
                score += 5
                feedback.append(f"'{code}' has only {len(subs)} items, expected 6 (5/15)")

    # 3. SCORING LOGIC (50 pts)
    # CalcP (20pts), CalcN (10pts), Balance (20pts)
    
    # Verify CalcP
    calc_p = get_q('CalcP')
    if calc_p and calc_p['type'] == '*': # '*' is Equation type
        logic = calc_p.get('question', '').lower()
        # Logic must contain 'sum' and reference 'SPANEP' OR contain '+'
        if ('sum' in logic and 'spanep' in logic) or ('+' in logic):
            score += 20
            feedback.append("CalcP logic appears valid (20/20)")
        else:
            feedback.append(f"CalcP logic invalid: '{logic}' (0/20)")
    else:
        feedback.append("CalcP equation question missing (0/20)")

    # Verify CalcN
    calc_n = get_q('CalcN')
    if calc_n and calc_n['type'] == '*':
        logic = calc_n.get('question', '').lower()
        if ('sum' in logic and 'spanen' in logic) or ('+' in logic):
            score += 10
            feedback.append("CalcN logic appears valid (10/10)")
        else:
            feedback.append(f"CalcN logic invalid (0/10)")
    else:
        feedback.append("CalcN equation question missing (0/10)")

    # Verify Balance
    balance = get_q('Balance')
    if balance and balance['type'] == '*':
        logic = balance.get('question', '').lower()
        # Must subtract
        if '-' in logic and ('calcp' in logic or 'calcn' in logic):
            score += 20
            feedback.append("Balance logic appears valid (20/20)")
        else:
            feedback.append(f"Balance logic does not subtract scores: '{logic}' (0/20)")
    else:
        feedback.append("Balance equation question missing (0/20)")

    # 4. PIPING SYNTAX (10 pts)
    # Look for a Text Display question (Type 'X') that uses piping
    text_display = next((q for q in questions if q['type'] == 'X'), None)
    if text_display:
        text = text_display.get('question', '')
        if '{' in text and '}' in text and ('CalcP' in text or 'Balance' in text):
            score += 10
            feedback.append("Result display uses piping syntax correctly (10/10)")
        else:
            feedback.append("Result display found but missing piping {variables} (0/10)")
    else:
        feedback.append("No Text Display question found for results (0/10)")

    # ---------------------------------------------------------
    # FINAL RESULT
    # ---------------------------------------------------------
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }