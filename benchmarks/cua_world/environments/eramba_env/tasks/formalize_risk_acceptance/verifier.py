#!/usr/bin/env python3
"""
Verifier for formalize_risk_acceptance task.

Verifies:
1. Risk Strategy changed to Accept (ID 1)
2. Justification text added to description
3. Review date set correctly
4. PDF Evidence attached to the risk record
5. Changes happened during task window (Anti-gaming)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_formalize_risk_acceptance(traj, env_info, task_info):
    # 1. Setup & Environment Access
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get Metadata & Requirements
    metadata = task_info.get('metadata', {})
    required_strategy_id = metadata.get('required_strategy_id', 1) # 1 = Accept
    required_snippet = metadata.get('required_justification_snippet', "Board Directive 2025-Q1")
    required_date = metadata.get('required_review_date', "2025-12-31")
    required_file = metadata.get('attachment_filename', "CEO_Risk_SignOff.pdf")

    # 3. Read Result File from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Analyze Results
    score = 0
    feedback_parts = []
    
    # Check if risk exists
    if not result.get('risk_found', False):
        return {"passed": False, "score": 0, "feedback": "Target risk 'Legacy ERP - Windows 2008' was not found in the database."}

    task_start = result.get('task_start_time', 0)
    risk_modified = result.get('risk_modified_ts', 0)
    
    # Criterion 1: Risk Strategy (30 pts)
    # Strategy 1 is Accept in default Eramba install
    actual_strategy = result.get('strategy_id', 0)
    if int(actual_strategy) == int(required_strategy_id):
        score += 30
        feedback_parts.append("Risk strategy correctly set to Accept")
    else:
        feedback_parts.append(f"Incorrect strategy ID: {actual_strategy} (Expected {required_strategy_id})")

    # Criterion 2: Evidence Attachment (30 pts)
    # Must exist and be created during task
    att_found = result.get('attachment_found', False)
    att_created = result.get('attachment_created_ts', 0)
    
    if att_found:
        if att_created > task_start:
            score += 30
            feedback_parts.append("Evidence file attached successfully")
        else:
            score += 10 # Partial credit if file exists but timestamp looks old (unlikely given setup, but safe)
            feedback_parts.append("Evidence file present but timestamp predates task")
    else:
        feedback_parts.append("Evidence file NOT attached")

    # Criterion 3: Justification in Description (20 pts)
    description = result.get('description', "")
    if required_snippet in description:
        score += 20
        feedback_parts.append("Justification text added to description")
    else:
        feedback_parts.append("Justification text missing from description")

    # Criterion 4: Review Date (10 pts)
    # Date format from MySQL is usually YYYY-MM-DD
    actual_date = result.get('review_date', "").split(' ')[0] # Handle potential timestamps
    if actual_date == required_date:
        score += 10
        feedback_parts.append("Review date correctly set")
    else:
        feedback_parts.append(f"Incorrect review date: {actual_date}")

    # Criterion 5: Anti-gaming / Modification check (10 pts)
    if risk_modified > task_start:
        score += 10
        feedback_parts.append("Risk record modified during task session")
    else:
        feedback_parts.append("No modification detected during task session")

    # 5. Determine Pass/Fail
    # Pass threshold: 60 pts
    # Must have at least Strategy Change AND Attachment (the core "Formalize" actions)
    core_requirements_met = (int(actual_strategy) == int(required_strategy_id)) and att_found
    passed = (score >= 60) and core_requirements_met

    final_feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }