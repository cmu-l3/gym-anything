#!/usr/bin/env python3
"""
Verifier for viral_churn_risk_analysis task.

Criteria:
1. Schema: 'FiledTicket' edge class exists (10 pts)
2. Schema: 'ChurnRisk' property exists on Profiles (10 pts)
3. Linkage: 'FiledTicket' edge connects matching Profile and Ticket (20 pts)
4. Logic: Friend of High-severity ticket filer is marked ChurnRisk=true (30 pts)
5. Logic: Friend of Low-severity ticket filer is NOT marked (10 pts)
6. Output: JSON file contains correct email (20 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_viral_churn_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
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

    db_state = result.get("db_state", {})
    output_exists = result.get("output_file_exists", False)
    
    # Clean up raw content (remove escaped quotes if necessary for parsing)
    raw_content = result.get("output_file_content_raw", "[]")
    try:
        output_content = json.loads(raw_content.replace('\\"', '"'))
    except:
        # If replace failed, try loading directly
        try:
             output_content = json.loads(raw_content)
        except:
             output_content = []

    score = 0
    feedback = []

    # Criterion 1: Schema - FiledTicket (10 pts)
    if db_state.get("filed_ticket_class_exists"):
        score += 5
        if db_state.get("filed_ticket_extends_e"):
            score += 5
            feedback.append("Schema: FiledTicket edge class created correctly.")
        else:
            feedback.append("Schema: FiledTicket created but does not extend E.")
    else:
        feedback.append("Schema: FiledTicket class not found.")

    # Criterion 2: Schema - ChurnRisk (10 pts)
    if db_state.get("churn_risk_property_exists"):
        score += 10
        feedback.append("Schema: ChurnRisk property added.")
    else:
        feedback.append("Schema: ChurnRisk property missing on Profiles.")

    # Criterion 3: Linkage (20 pts)
    linked_count = db_state.get("john_linked_count", 0)
    if linked_count >= 1:
        score += 20
        feedback.append("Linkage: Profiles linked to Tickets successfully.")
    else:
        feedback.append("Linkage: Failed to link 'john.smith@example.com' to his ticket.")

    # Criterion 4: Logic - High Risk Friend (Maria) (30 pts)
    # Maria is friend of John (High). Should be true.
    maria_val = db_state.get("maria_risk_val")
    # OrientDB booleans can be True, true, 1
    if maria_val is True or str(maria_val).lower() == "true":
        score += 30
        feedback.append("Logic: High-risk friend (Maria) correctly flagged.")
    else:
        feedback.append(f"Logic: High-risk friend (Maria) NOT flagged. Value: {maria_val}")

    # Criterion 5: Logic - Low Risk Friend (Sophie) (10 pts)
    # Sophie is friend of David (Low). Should be None or False.
    sophie_val = db_state.get("sophie_risk_val")
    if sophie_val is None or sophie_val is False or str(sophie_val).lower() == "false":
        score += 10
        feedback.append("Logic: Low-risk friend (Sophie) correctly ignored.")
    else:
        feedback.append(f"Logic: Low-risk friend (Sophie) incorrectly flagged. Value: {sophie_val}")

    # Criterion 6: Output File (20 pts)
    target_email = "maria.garcia@example.com"
    if output_exists:
        if isinstance(output_content, list) and target_email in output_content:
            score += 20
            feedback.append("Output: JSON file contains correct target email.")
        else:
            feedback.append(f"Output: File exists but content incorrect. Expected list containing '{target_email}'. Got: {str(output_content)[:50]}")
    else:
        feedback.append("Output: ~/at_risk_users.json not found.")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }