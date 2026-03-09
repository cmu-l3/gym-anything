#!/usr/bin/env python3
"""
Verifier for CRM Integration URL Params task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_crm_integration(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Check Survey Existence (10 pts)
    if not result.get("survey_found"):
        return {"passed": False, "score": 0, "feedback": "Survey 'Zendesk Support Feedback 2025' not found."}
    
    score += 10
    feedback.append("Survey created.")

    # 2. Check System Questions Existence and Codes (15 pts)
    questions = result.get("questions", [])
    q_codes = {q['code']: q for q in questions}
    
    required_codes = ["Q_Ticket", "Q_Agent", "Q_Channel"]
    missing_codes = [c for c in required_codes if c not in q_codes]
    
    if not missing_codes:
        score += 15
        feedback.append("System questions (Q_Ticket, Q_Agent, Q_Channel) created.")
    else:
        feedback.append(f"Missing system questions: {missing_codes}")

    # 3. Check Hidden Attribute (20 pts)
    # Check if Q_Ticket, Q_Agent, Q_Channel have hidden=1 attribute
    attributes = result.get("attributes", [])
    hidden_qids = [attr['qid'] for attr in attributes if attr['attribute'] == 'hidden' and attr['value'] == '1']
    
    hidden_count = 0
    for code in required_codes:
        if code in q_codes:
            qid = q_codes[code]['qid']
            if qid in hidden_qids:
                hidden_count += 1
    
    if hidden_count == 3:
        score += 20
        feedback.append("All system questions set to hidden.")
    elif hidden_count > 0:
        score += int((hidden_count / 3) * 20)
        feedback.append(f"Partial hidden questions: {hidden_count}/3.")
    else:
        feedback.append("System questions are NOT hidden.")

    # 4. Check URL Parameters Configuration (30 pts)
    # Mapping: ext_tid -> Q_Ticket, ext_ag -> Q_Agent, ext_chn -> Q_Channel
    url_params = result.get("url_params", [])
    # Convert DB result to dict: param_name -> target_qid
    param_map = {p['parameter']: p['targetqid'] for p in url_params}
    
    mapping_score = 0
    mapping_targets = {
        "ext_tid": "Q_Ticket",
        "ext_ag": "Q_Agent",
        "ext_chn": "Q_Channel"
    }
    
    correct_mappings = 0
    for param, target_code in mapping_targets.items():
        if target_code in q_codes:
            target_qid = q_codes[target_code]['qid']
            # Check if param exists and maps to target_qid
            if param in param_map and str(param_map[param]) == str(target_qid):
                correct_mappings += 1
    
    if correct_mappings == 3:
        score += 30
        feedback.append("URL parameters correctly mapped.")
    else:
        score += correct_mappings * 10
        feedback.append(f"URL parameters mapping incomplete: {correct_mappings}/3 correct.")

    # 5. Check Piping Syntax (20 pts)
    # Find satisfaction question
    satisfaction_q = next((q for q in questions if q['code'] == 'Satisfaction'), None)
    if satisfaction_q:
        text = satisfaction_q['text']
        if "{Q_Channel}" in text and "{Q_Agent}" in text:
            score += 20
            feedback.append("Piping syntax correctly used.")
        else:
            feedback.append("Piping syntax missing or incorrect in Satisfaction question.")
    else:
        feedback.append("Satisfaction question not found.")

    # 6. Check Active (5 pts)
    if result.get("is_active"):
        score += 5
        feedback.append("Survey is active.")
    else:
        feedback.append("Survey is NOT active.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }