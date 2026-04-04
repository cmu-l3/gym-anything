#!/usr/bin/env python3
"""
Verifier for chinook_pii_anonymization task.
Checks DBeaver connection, database state (anonymization logic), and output files.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_pii_anonymization(traj, env_info, task_info):
    """
    Verify the PII anonymization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection (8 pts)
    if result.get("dbeaver_connection_exists"):
        score += 8
        feedback.append("DBeaver connection confirmed.")
    else:
        feedback.append("DBeaver 'ChinookVendor' connection not found.")

    # 2. Database Anonymization Logic (60 pts)
    # DB must have been modified
    if not result.get("db_modified"):
        feedback.append("Database file was not modified.")
    else:
        # FirstName (10 pts)
        if result.get("first_name_correct"):
            score += 10
            feedback.append("First names anonymized.")
        else:
            feedback.append("First name anonymization failed.")

        # LastName (10 pts)
        if result.get("last_name_correct"):
            score += 10
            feedback.append("Last names anonymized (padded format).")
        else:
            feedback.append("Last name anonymization incorrect (check C000 format).")

        # Email (12 pts)
        if result.get("email_correct"):
            score += 12
            feedback.append("Emails anonymized.")
        else:
            feedback.append("Email anonymization incorrect.")

        # Address (8 pts)
        if result.get("address_correct"):
            score += 8
            feedback.append("Addresses redacted.")
        else:
            feedback.append("Address redaction failed.")

        # Phone/Fax (10 pts)
        if result.get("phone_fax_correct"):
            score += 10
            feedback.append("Phone/Fax nulled.")
        else:
            feedback.append("Phone/Fax not cleared.")

        # Company Logic (10 pts)
        if result.get("company_correct"):
            score += 10
            feedback.append("Company fields handled correctly (REDACTED vs NULL).")
        else:
            feedback.append("Company field logic incorrect.")

    # 3. Integrity & Preservation (9 pts)
    if result.get("non_pii_preserved"):
        score += 5
    else:
        feedback.append("Warning: Non-PII fields (like Country) seem modified/wiped.")
        
    if result.get("integrity_preserved") and result.get("row_count", 0) == 59:
        score += 4
    elif result.get("row_count", 0) != 59:
        feedback.append("Customer row count changed (records deleted?).")

    # 4. Deliverables (23 pts)
    # Report
    if result.get("report_exists"):
        if result.get("report_valid") and result.get("report_row_count", 0) >= 7:
            score += 15
            feedback.append("Audit report CSV valid.")
        else:
            score += 5
            feedback.append("Audit report exists but content/format is issues.")
    else:
        feedback.append("Audit report missing.")

    # Script
    if result.get("script_exists"):
        if result.get("script_valid"):
            score += 8
            feedback.append("SQL script valid.")
        else:
            score += 4
            feedback.append("SQL script exists but may be empty.")
    else:
        feedback.append("SQL script missing.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }