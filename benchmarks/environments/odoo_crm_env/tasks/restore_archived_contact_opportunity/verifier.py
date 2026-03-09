#!/usr/bin/env python3
"""
Verifier for restore_archived_contact_opportunity task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restore_archived_contact_opportunity(traj, env_info, task_info):
    """
    Verify that the contact was restored, updated, and an opportunity created.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Expected values
    metadata = task_info.get('metadata', {})
    expected_phone = metadata.get('expected_phone', "+1-415-555-0200")
    expected_revenue = metadata.get('expected_revenue', 75000)
    
    # Retrieve result from container
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
    feedback_parts = []
    
    # Extract data
    contact_active = result.get('contact_active', False)
    contact_phone = result.get('contact_phone', '')
    contact_city = result.get('contact_city', '')
    contact_street = result.get('contact_street', '')
    contact_state = result.get('contact_state', '')
    
    opp_exists = result.get('opportunity_exists', False)
    opp_revenue = result.get('opportunity_revenue', 0)
    opp_priority = result.get('opportunity_priority', "0")
    opp_partner_name = result.get('opportunity_partner_name', '')
    
    task_start = result.get('task_start_time', 0)
    contact_write = result.get('contact_write_date_epoch', 0)
    opp_create = result.get('opportunity_create_date_epoch', 0)

    # --- Criterion 1: Contact Restored (20 pts) ---
    if contact_active:
        score += 20
        feedback_parts.append("Contact restored (active)")
    else:
        feedback_parts.append("Contact NOT active/found")

    # --- Criterion 2: Contact Details Updated (30 pts) ---
    # Phone (10 pts)
    # Normalize phone for comparison (remove spaces, parens, dashes)
    def normalize_phone(p):
        return ''.join(filter(str.isdigit, p or ''))
    
    if normalize_phone(expected_phone) in normalize_phone(contact_phone):
        score += 10
        feedback_parts.append("Phone updated")
    else:
        feedback_parts.append(f"Phone mismatch ({contact_phone})")

    # City (10 pts)
    if "san francisco" in contact_city.lower():
        score += 10
        feedback_parts.append("City updated")
    else:
        feedback_parts.append(f"City mismatch ({contact_city})")
        
    # Street (5 pts)
    if "785 market" in contact_street.lower():
        score += 5
        feedback_parts.append("Street updated")
    
    # State (5 pts)
    if "california" in contact_state.lower():
        score += 5
        feedback_parts.append("State updated")

    # --- Criterion 3: Opportunity Created (20 pts) ---
    if opp_exists:
        score += 20
        feedback_parts.append("Opportunity created")
    else:
        feedback_parts.append("Opportunity NOT found")

    # --- Criterion 4: Opportunity Details (30 pts) ---
    if opp_exists:
        # Linked to contact (15 pts)
        if "meridian technologies" in opp_partner_name.lower():
            score += 15
            feedback_parts.append("Opportunity linked to correct contact")
        else:
            feedback_parts.append(f"Opportunity linked to wrong partner ({opp_partner_name})")
            
        # Revenue (10 pts)
        if float(opp_revenue) == float(expected_revenue):
            score += 10
            feedback_parts.append("Revenue correct")
        else:
            feedback_parts.append(f"Revenue incorrect ({opp_revenue})")
            
        # Priority (5 pts)
        # Odoo priority '2' often corresponds to High/3-stars depending on theme, standard is '0','1','2','3'
        if str(opp_priority) == "2":
            score += 5
            feedback_parts.append("Priority correct")
        else:
            feedback_parts.append(f"Priority incorrect ({opp_priority})")

    # --- Anti-Gaming Checks ---
    # Ensure modifications happened after task start
    if contact_active and contact_write > 0 and contact_write <= task_start:
        feedback_parts.append("WARNING: Contact modified before task start!")
        score = 0
    
    if opp_exists and opp_create > 0 and opp_create <= task_start:
        feedback_parts.append("WARNING: Opportunity created before task start!")
        score = 0

    # Final Pass Determination
    # Must have restored contact AND created opportunity to reasonably pass
    pass_threshold = 60
    passed = (score >= pass_threshold) and contact_active and opp_exists

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }