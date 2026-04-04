#!/usr/bin/env python3
"""
Verifier for IT Asset Inventory Validation Task.
Checks if the agent correctly applied Regex validation and Expression Manager logic.
"""

import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_it_asset_validation(traj, env_info, task_info):
    """
    Verify the IT Asset Validation task.
    
    Criteria:
    1. Survey 'IT Asset Audit 2025' exists.
    2. 'AssetTag' question has correct Regex.
    3. 'MacAddr' question has correct Regex.
    4. 'WarrYear' question has correct logic equation (>= PurchYear).
    5. User tips (help text) are set for these fields.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    try:
        import tempfile
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    if not result.get('survey_found'):
        return {"passed": False, "score": 0, "feedback": "Survey 'IT Asset Audit 2025' not found."}

    questions = result.get('questions', [])
    if isinstance(questions, dict) and 'error' in questions:
         return {"passed": False, "score": 0, "feedback": f"Database error: {questions['error']}"}

    # Helper to find question by code
    def get_q(code):
        for q in questions:
            if q.get('code') == code:
                return q
        return None

    score = 0
    feedback = []

    # 1. Verify Asset Tag (30 pts)
    # Expect Regex: IT-[0-9]{5}
    q_asset = get_q('AssetTag')
    if q_asset:
        preg = q_asset.get('preg', '')
        help_text = q_asset.get('help', '')
        
        # Check Regex
        if 'IT-' in preg and '[0-9]{5}' in preg:
            score += 20
            feedback.append("AssetTag Regex correct.")
        elif preg:
            score += 5
            feedback.append(f"AssetTag Regex incorrect: found '{preg}', expected 'IT-[0-9]{{5}}'.")
        else:
            feedback.append("AssetTag Regex missing.")

        # Check Help
        if 'IT-' in help_text:
            score += 10
            feedback.append("AssetTag help text correct.")
        else:
            feedback.append("AssetTag help text missing or incorrect.")
    else:
        feedback.append("Question 'AssetTag' not found.")

    # 2. Verify MAC Address (30 pts)
    # Expect Regex similar to ^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$
    # We'll check for key components since exact string might vary slightly
    q_mac = get_q('MacAddr')
    if q_mac:
        preg = q_mac.get('preg', '')
        help_text = q_mac.get('help', '')
        
        # Check Regex (look for hex logic)
        if '[0-9A-Fa-f]' in preg or '[0-9a-fA-F]' in preg:
            if '{2}' in preg and ':' in preg:
                score += 20
                feedback.append("MacAddr Regex correct.")
            else:
                score += 10
                feedback.append("MacAddr Regex partial match.")
        elif preg:
            score += 5
            feedback.append(f"MacAddr Regex incorrect: found '{preg}'.")
        else:
            feedback.append("MacAddr Regex missing.")

        # Check Help
        if 'XX:' in help_text or 'xx:' in help_text:
            score += 10
            feedback.append("MacAddr help text correct.")
        else:
            feedback.append("MacAddr help text missing.")
    else:
        feedback.append("Question 'MacAddr' not found.")

    # 3. Verify Warranty Logic (30 pts)
    # Expect Equation: WarrYear >= PurchYear
    q_warr = get_q('WarrYear')
    if q_warr:
        eq = q_warr.get('validation_equation', '')
        help_text = q_warr.get('help', '')
        
        # Check Equation
        # Remove spaces and .NAOK for flexible matching
        clean_eq = eq.replace(' ', '').replace('.NAOK', '')
        if 'WarrYear>=PurchYear' in clean_eq or 'WarrYear>PurchYear' in clean_eq:
            score += 20
            feedback.append("Warranty logic equation correct.")
        elif eq:
            score += 5
            feedback.append(f"Warranty logic incorrect: found '{eq}'.")
        else:
            feedback.append("Warranty logic equation missing.")
            
        # Check Help
        if 'Warranty' in help_text and 'purchase' in help_text.lower():
            score += 10
            feedback.append("Warranty help text correct.")
        else:
            feedback.append("Warranty help text missing.")
    else:
        feedback.append("Question 'WarrYear' not found.")
        
    # Base points for creating survey
    if score > 0:
        score += 10 # 10 pts for structure
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }