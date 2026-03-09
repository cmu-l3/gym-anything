#!/usr/bin/env python3
"""
Verifier for dynamic_subquestion_relevance_config task.

Evaluates:
1. Survey creation and activation.
2. Correct Question Codes (DEPT, TOOLS).
3. Correct Answer Codes for DEPT (SALES, ENG, LEGAL) - essential for logic.
4. Correct Expression Manager logic on TOOLS subquestions.
"""

import json
import os
import tempfile
import re

def verify_dynamic_subquestion_relevance_config(traj, env_info, task_info):
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

    score = 0
    feedback = []

    # 1. Survey Existence & Activation (20 pts)
    if result.get('survey_found'):
        score += 10
        if result.get('survey_active') == 'Y':
            score += 10
            feedback.append("Survey created and active.")
        else:
            feedback.append("Survey created but NOT active.")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey 'New Hire IT Provisioning 2025' not found."}

    # 2. Question Setup (20 pts)
    dept_qid = result.get('dept_qid')
    tools_qid = result.get('tools_qid')
    
    if dept_qid and tools_qid:
        score += 20
        feedback.append("Questions DEPT and TOOLS found.")
    else:
        feedback.append(f"Missing questions: DEPT={bool(dept_qid)}, TOOLS={bool(tools_qid)}.")

    # 3. DEPT Answer Codes (20 pts)
    # Essential because logic depends on these specific codes
    dept_raw = result.get('dept_answers_raw', '')
    # Expected format from export: SALES:Sales|ENG:Engineering|LEGAL:Legal|
    
    required_codes = ['SALES', 'ENG', 'LEGAL']
    codes_found = 0
    for code in required_codes:
        if f"{code}:" in dept_raw:
            codes_found += 1
            
    if codes_found == 3:
        score += 20
        feedback.append("DEPT answer codes correct.")
    else:
        score += (codes_found * 5)
        feedback.append(f"Incorrect DEPT answer codes. Found {codes_found}/3 required codes.")

    # 4. Subquestion Logic (40 pts)
    # Expected format from export: SF||relevance;VS||relevance;...
    tools_logic_raw = result.get('tools_logic_raw', '')
    
    # Parse into a dictionary: {code: relevance_string}
    logic_map = {}
    if tools_logic_raw:
        for entry in tools_logic_raw.split(';'):
            if '||' in entry:
                code, logic = entry.split('||', 1)
                logic_map[code.strip()] = logic.strip()

    # Logic Check Helper
    def check_logic(code, keywords):
        # returns True if all keywords exist in the relevance string for the code
        rule = logic_map.get(code, "")
        if not rule: 
            return False
        # Normalize: remove spaces, lowercase
        rule_norm = re.sub(r'\s+', '', rule.lower())
        for k in keywords:
            if k.lower() not in rule_norm:
                return False
        return True

    # Scoring Logic
    # SF (Salesforce): DEPT == "SALES"
    if check_logic("SF", ["DEPT", "SALES", "=="]):
        score += 10
    else:
        feedback.append("Logic for 'SF' (Salesforce) incorrect.")

    # VS (Visual Studio): DEPT == "ENG"
    if check_logic("VS", ["DEPT", "ENG", "=="]):
        score += 10
    else:
        feedback.append("Logic for 'VS' (Visual Studio) incorrect.")

    # LN (LexisNexis): DEPT == "LEGAL"
    if check_logic("LN", ["DEPT", "LEGAL", "=="]):
        score += 10
    else:
        feedback.append("Logic for 'LN' (LexisNexis) incorrect.")

    # SL (Slack): DEPT == "SALES" OR DEPT == "ENG"
    # Check for DEPT, SALES, ENG, and an OR operator
    slack_rule = logic_map.get("SL", "").lower()
    if "dept" in slack_rule and "sales" in slack_rule and "eng" in slack_rule and (" or " in slack_rule or "||" in slack_rule):
        score += 10
    else:
        feedback.append("Logic for 'SL' (Slack) incorrect (must enable for Sales OR Eng).")
        
    # Bonus Check: Office (OFF) should always be visible (empty or 1)
    off_rule = logic_map.get("OFF", "1").strip()
    if off_rule == "1" or off_rule == "":
        # No points, just good practice check
        pass
    elif "dept" in off_rule.lower():
        feedback.append("Warning: 'OFF' (Office) has conditions but should be always visible.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }