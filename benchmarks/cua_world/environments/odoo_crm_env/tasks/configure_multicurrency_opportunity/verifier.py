#!/usr/bin/env python3
import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_multicurrency_opportunity(traj, env_info, task_info):
    """
    Verify the configure_multicurrency_opportunity task.
    
    Criteria:
    1. EUR currency is active (25 pts)
    2. Opportunity exists (20 pts)
    3. Opportunity currency is EUR (30 pts)
    4. Partner is correct (15 pts)
    5. Revenue is correct (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_currency = metadata.get('target_currency', 'EUR')
    target_revenue = metadata.get('target_revenue', 125000.0)
    target_partner = metadata.get('target_partner', 'Bavaria Logistics GmbH')

    # Copy result file
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

    score = 0
    feedback = []
    
    # 1. Verify EUR is active
    eur_active = result.get('eur_active', False)
    eur_id = result.get('eur_id')
    if eur_active:
        score += 25
        feedback.append("EUR currency successfully activated.")
    else:
        feedback.append("EUR currency is NOT active.")

    # 2. Verify Opportunity Exists
    opp_found = result.get('opportunity_found', False)
    opp_data = result.get('opportunity_data', {})
    
    if opp_found:
        score += 20
        feedback.append("Opportunity created.")
        
        # 3. Verify Opportunity Currency
        # The export script extracts the ID. We compare it with the EUR ID captured.
        opp_currency_id = opp_data.get('currency_id')
        
        # Odoo default currency (USD) is usually ID 1 or 2, EUR usually distinct.
        # If eur_id is None (because it wasn't found), this check fails naturally.
        if eur_id and opp_currency_id == eur_id:
            score += 30
            feedback.append("Opportunity is correctly denominated in EUR.")
        else:
            feedback.append(f"Opportunity currency ID ({opp_currency_id}) does not match EUR ID ({eur_id}). Likely still in USD.")

        # 4. Verify Partner
        # Allow partial match or case insensitive
        actual_partner = opp_data.get('partner_name', '')
        if target_partner.lower() in actual_partner.lower():
            score += 15
            feedback.append(f"Partner '{actual_partner}' is correct.")
        else:
            feedback.append(f"Partner mismatch. Expected '{target_partner}', got '{actual_partner}'.")

        # 5. Verify Revenue
        actual_revenue = opp_data.get('expected_revenue', 0)
        # Allow slight float tolerance
        if abs(float(actual_revenue) - float(target_revenue)) < 1.0:
            score += 10
            feedback.append(f"Revenue {actual_revenue} is correct.")
        else:
            feedback.append(f"Revenue mismatch. Expected {target_revenue}, got {actual_revenue}.")

    else:
        feedback.append("Target opportunity not found.")

    # Anti-gaming: Check timestamps if available
    # Simple check: if opportunity creation date is present, it implies it was created
    # The Setup script deletes the opportunity, so existence implies creation during task or right before.
    # A stricter check would compare timestamps, but Odoo returns strings 'YYYY-MM-DD HH:MM:SS'.
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }