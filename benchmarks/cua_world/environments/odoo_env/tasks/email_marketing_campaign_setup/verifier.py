#!/usr/bin/env python3
"""
Verifier for email_marketing_campaign_setup task.
Scores the agent on:
1. Creating the correct mailing list.
2. Importing contacts correctly.
3. Creating the mailing campaign with correct content.
4. Scheduling the campaign for the correct date.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_marketing_campaign_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load setup data (for target date) and result data
    temp_setup = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        # Try to get setup data
        target_date_str = None
        try:
            copy_from_env("/tmp/marketing_setup.json", temp_setup.name)
            with open(temp_setup.name, 'r') as f:
                setup_data = json.load(f)
                target_date_str = setup_data.get('target_date')
        except Exception:
            logger.warning("Could not load setup data, relying on task description logic.")

        # Get result data
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result files: {e}"}
    finally:
        if os.path.exists(temp_setup.name): os.unlink(temp_setup.name)
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Mailing List Creation (10 pts)
    if result.get("list_found"):
        score += 10
        feedback_parts.append("Mailing list created successfully.")
    else:
        feedback_parts.append("Mailing list 'Eco-Conscious Interest Group' not found.")

    # 2. Verify Contacts Import (20 pts)
    # Expect 3 specific emails
    found_emails = result.get("correct_emails_found", [])
    if len(found_emails) == 3:
        score += 20
        feedback_parts.append(f"All 3 contacts imported correctly.")
    elif len(found_emails) > 0:
        partial_score = int((len(found_emails) / 3) * 20)
        score += partial_score
        feedback_parts.append(f"Partial contacts import ({len(found_emails)}/3 found).")
    else:
        feedback_parts.append("No correct contacts found in the list.")

    # 3. Verify Mailing Campaign Existence & Linking (20 pts)
    mailing = result.get("mailing_details", {})
    if result.get("mailing_found"):
        if mailing.get("targets_correct_list"):
            score += 20
            feedback_parts.append("Mailing created and targets the correct list.")
        else:
            score += 10
            feedback_parts.append("Mailing created but does not target the correct list.")
    else:
        feedback_parts.append("No relevant mailing campaign found (checked subject 'Bamboo').")
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 4. Verify Subject & Body (30 pts)
    # Subject check was implicitly done by the search in export script, but let's confirm exact match if needed
    # We allocated 10 pts for subject in design, already partially covered by finding it.
    # Let's verify body content explicitly.
    
    body_content = mailing.get("body_content", "")
    if "BAMBOO25" in body_content:
        score += 20
        feedback_parts.append("Discount code found in email body.")
    else:
        feedback_parts.append("Discount code 'BAMBOO25' missing from email body.")

    # Subject explicit check (10 pts)
    subject = mailing.get("subject", "")
    if "Sustainable Bamboo Collection" in subject:
        score += 10
        feedback_parts.append("Subject line is correct.")
    else:
        feedback_parts.append("Subject line content incorrect.")

    # 5. Verify Scheduling (20 pts)
    # State must be 'schedule' (which means In Queue/Scheduled in Odoo backend)
    # Date must match target date
    state = mailing.get("state")
    schedule_date = mailing.get("schedule_date") # Format YYYY-MM-DD HH:MM:SS usually
    
    if state == 'schedule': # 'schedule' is the technical value for "Scheduled"
        if target_date_str and schedule_date and target_date_str in schedule_date:
            score += 20
            feedback_parts.append(f"Campaign successfully scheduled for {target_date_str}.")
        else:
            score += 10
            feedback_parts.append(f"Campaign is in scheduled state, but date '{schedule_date}' does not match target '{target_date_str}'.")
    else:
        feedback_parts.append(f"Campaign is not in 'Scheduled' state (current state: {state}).")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }