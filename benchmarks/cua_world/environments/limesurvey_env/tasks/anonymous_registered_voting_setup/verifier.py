#!/usr/bin/env python3
"""
Verifier for Anonymous Registered Voting Setup task.

Criteria:
1. Survey '2025 Employee Benefits Vote' exists.
2. Anonymized responses = 'Y' (Critical security feature).
3. Public registration = 'Y' (Critical access feature).
4. Token table initialized.
5. Custom attribute 'EmployeeID' created.
6. Registration email customized.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_anonymous_registered_voting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/voting_result.json", tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    
    # 1. Survey Exists (Gate)
    if not result.get("survey_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Survey '2025 Employee Benefits Vote' not found."
        }
    score += 10
    feedback_parts.append("Survey created [10/10]")

    # 2. Anonymity (Critical - 25 pts)
    anon = result.get("anonymized", "N")
    if anon == "Y":
        score += 25
        feedback_parts.append("Anonymity enabled [25/25]")
    else:
        feedback_parts.append("Anonymity NOT enabled (Critical failure for secret ballot) [0/25]")

    # 3. Public Registration (Critical - 20 pts)
    reg = result.get("allow_register", "N")
    if reg == "Y":
        score += 20
        feedback_parts.append("Public registration enabled [20/20]")
    else:
        feedback_parts.append("Public registration NOT enabled [0/20]")

    # 4. Token Table Initialized (10 pts)
    if result.get("tokens_initialized"):
        score += 10
        feedback_parts.append("Participants table initialized [10/10]")
    else:
        feedback_parts.append("Participants table NOT initialized [0/10]")

    # 5. Custom Attribute (15 pts)
    if result.get("attribute_found"):
        score += 15
        feedback_parts.append("Custom attribute 'EmployeeID' found [15/15]")
    else:
        feedback_parts.append("Attribute 'EmployeeID' not found in participant settings [0/15]")

    # 6. Email Customization (20 pts)
    email_score = 0
    if result.get("email_subject_correct"):
        email_score += 10
    else:
        feedback_parts.append(f"Email subject mismatch (Got: {result.get('raw_subject')})")
        
    if result.get("email_body_correct"):
        email_score += 10
        
    if email_score == 20:
        feedback_parts.append("Email fully customized [20/20]")
    elif email_score > 0:
        feedback_parts.append(f"Email partially customized [{email_score}/20]")
    else:
        feedback_parts.append("Email template not updated [0/20]")
    
    score += email_score

    # Check activation (Bonus/Tie-breaker check, though not strictly heavily weighted if config is right)
    active = result.get("active", "N")
    if active == "Y":
        feedback_parts.append("(Survey is active)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }