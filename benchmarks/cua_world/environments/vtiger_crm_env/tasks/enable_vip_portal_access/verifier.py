#!/usr/bin/env python3
"""
Verifier for enable_vip_portal_access task.
Validates multi-module interaction: updating an existing Contact and linking a newly created Ticket.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_vip_portal_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Read result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    c_found = result.get('contact_found', False)
    t_found = result.get('ticket_found', False)
    task_start = result.get('task_start_time', 0)
    
    # Early fail if the contact was completely lost/deleted
    if not c_found:
        return {
            "passed": False,
            "score": 0,
            "feedback": "FAILED: The expected contact 'Elena Rostova' could not be found in the system."
        }

    c_modified = int(result.get('contact_modified_time', 0))
    t_created = int(result.get('ticket_created_time', 0))
    
    # Anti-gaming: Ensure the modifications happened during the task run
    if c_modified > 0 and c_modified >= task_start:
        feedback_parts.append("Contact modification verified in timestamp.")
    
    # -------------------------------------------------------------------------
    # Criterion 1: Contact Title & Dept Updated (15 points)
    # -------------------------------------------------------------------------
    c_title = str(result.get('contact_title', '')).strip()
    c_dept = str(result.get('contact_department', '')).strip()
    
    if c_title.lower() == metadata['expected_title'].lower() and c_dept.lower() == metadata['expected_department'].lower():
        score += 15
        feedback_parts.append("Contact Basic Info (Title/Dept) updated successfully (+15)")
    else:
        feedback_parts.append(f"Contact Info mismatch. Expected: {metadata['expected_title']} / {metadata['expected_department']}. Got: {c_title} / {c_dept}")

    # -------------------------------------------------------------------------
    # Criterion 2: Portal User Enabled (20 points)
    # -------------------------------------------------------------------------
    # Vtiger stores checkbox states often as '1' or '0' (int or str)
    c_portal = str(result.get('contact_portal', '0')).strip()
    if c_portal == '1' or c_portal.lower() == 'on' or c_portal.lower() == 'true':
        score += 20
        feedback_parts.append("Customer Portal enabled successfully (+20)")
    else:
        feedback_parts.append("Customer Portal was NOT enabled.")

    # -------------------------------------------------------------------------
    # Criterion 3: Entitlement Dates (25 points)
    # -------------------------------------------------------------------------
    c_start = str(result.get('contact_support_start', '')).strip()
    c_end = str(result.get('contact_support_end', '')).strip()
    
    dates_correct = False
    if c_start == metadata['expected_support_start'] and c_end == metadata['expected_support_end']:
        dates_correct = True
        score += 25
        feedback_parts.append("Support entitlement dates set correctly (+25)")
    else:
        feedback_parts.append(f"Support dates mismatch. Expected: {metadata['expected_support_start']} to {metadata['expected_support_end']}. Got: {c_start} to {c_end}")

    # -------------------------------------------------------------------------
    # Criterion 4: Ticket Creation Details (15 points)
    # -------------------------------------------------------------------------
    if t_found:
        if t_created >= task_start:
            t_status = str(result.get('ticket_status', '')).strip()
            t_priority = str(result.get('ticket_priority', '')).strip()
            
            if t_status == metadata['expected_ticket_status'] and t_priority == metadata['expected_ticket_priority']:
                score += 15
                feedback_parts.append("Ticket created with correct Status and Priority (+15)")
            else:
                score += 5  # Partial for creating it, but wrong status/priority
                feedback_parts.append(f"Ticket created, but wrong details. Expected Status: {metadata['expected_ticket_status']}, Priority: {metadata['expected_ticket_priority']}")
        else:
            feedback_parts.append("Ticket found, but timestamp indicates it was created before task started.")
    else:
        feedback_parts.append("Required Onboarding Ticket was NOT created.")

    # -------------------------------------------------------------------------
    # Criterion 5: Ticket Linked to Contact (25 points)
    # -------------------------------------------------------------------------
    if t_found:
        c_id = str(result.get('contact_id', '')).strip()
        t_contact_id = str(result.get('ticket_contact_id', '')).strip()
        
        # Validates relation linking the ticket explicitly to Elena
        if t_contact_id == c_id and c_id != "":
            score += 25
            feedback_parts.append("Ticket successfully linked to Contact 'Elena Rostova' (+25)")
        else:
            feedback_parts.append("Ticket was created but NOT linked to the target Contact record.")

    # -------------------------------------------------------------------------
    # Final Evaluation
    # -------------------------------------------------------------------------
    # Pass requires a score of 75, AND enabling the portal, AND linking the ticket
    key_criteria_met = (c_portal in ['1', 'on', 'true']) and (t_found and t_contact_id == c_id)
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }