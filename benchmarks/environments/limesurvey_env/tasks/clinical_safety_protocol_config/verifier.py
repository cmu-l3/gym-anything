#!/usr/bin/env python3
"""
Verifier for clinical_safety_protocol_config task.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_clinical_safety_protocol_config(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    metadata = task_info.get("metadata", {})
    target_email = metadata.get("target_email", "dr.patel@clinical-safety.org")
    
    # 1. Verify Notification Logic (35 pts)
    email_setting = result.get("email_alert_to", "")
    
    # Needs to be an expression, not just the email
    has_logic_start = "if(" in email_setting.lower() or "if (" in email_setting.lower()
    has_target_email = target_email in email_setting
    has_condition_var = "safety_check" in email_setting
    
    if has_logic_start and has_target_email and has_condition_var:
        score += 35
        feedback_parts.append("Notification logic configured correctly")
    elif has_target_email:
        # Partial credit if they just put the email without logic (bad practice but partially correct intent)
        score += 5
        feedback_parts.append("Email target present but MISSING conditional logic (Expression Manager)")
    else:
        feedback_parts.append("Notification email/logic missing")

    # 2. Verify Intervention Question Exists (20 pts)
    q_data = result.get("intervention_question", {})
    if q_data.get("found"):
        q_text = q_data.get("text", "").lower()
        if "988" in q_text:
            score += 20
            feedback_parts.append("Crisis resource question created with correct content")
        else:
            score += 10
            feedback_parts.append("Text display question created but missing '988'")
    else:
        feedback_parts.append("Crisis resource text question NOT found")

    # 3. Verify Relevance Logic (35 pts)
    relevance = q_data.get("relevance", "")
    # Allow some variation in spacing/quotes
    # Expected: safety_check == "Y"
    norm_relevance = relevance.replace(" ", "").replace("'", '"')
    
    if 'safety_check=="Y"' in norm_relevance:
        score += 35
        feedback_parts.append("Display relevance logic correct")
    elif "safety_check" in relevance and "Y" in relevance:
        # Close enough but maybe syntax error
        score += 25
        feedback_parts.append("Relevance logic present but syntax may be inexact")
    elif q_data.get("found"):
        feedback_parts.append("Relevance logic missing or incorrect (Question always shows or never shows)")
    
    # 4. Survey State/Base points (10 pts)
    if result.get("sid"):
        score += 10

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }