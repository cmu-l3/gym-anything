#!/usr/bin/env python3
"""
Verifier for configure_polling_campaign@1 task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_polling_campaign(traj, env_info, task_info):
    """
    Verifies that the Vicidial campaign, statuses, script, and list were configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    campaign = result.get('campaign')
    statuses = result.get('statuses', [])
    script = result.get('script')
    list_info = result.get('list')
    
    # --- Criterion 1: Campaign Configuration (40 pts) ---
    if campaign and campaign.get('id') == 'SENPOLL':
        score += 15
        feedback_parts.append("Campaign SENPOLL created")
        
        # Name check (contains 'Senate' and 'Polling')
        c_name = campaign.get('name', '')
        if 'Senate' in c_name and 'Polling' in c_name:
             # Exact match check
             if c_name == 'Senate Office Polling 2026':
                 feedback_parts.append("Campaign name correct")
             else:
                 feedback_parts.append(f"Campaign name '{c_name}' acceptable")
        
        if campaign.get('dial_method') == 'RATIO':
            score += 10
            feedback_parts.append("Dial Method RATIO")
        else:
            feedback_parts.append(f"Wrong Dial Method: {campaign.get('dial_method')}")
            
        if str(campaign.get('auto_dial_level')) == '1.0' or str(campaign.get('auto_dial_level')) == '1':
            score += 10
            feedback_parts.append("Auto Dial Level 1.0")
        else:
            feedback_parts.append(f"Wrong Dial Level: {campaign.get('auto_dial_level')}")
            
        if campaign.get('active') == 'Y':
            score += 5
            feedback_parts.append("Campaign Active")
    else:
        feedback_parts.append("Campaign SENPOLL NOT found")

    # --- Criterion 2: Statuses (20 pts) ---
    # Expected: SVYCMP, REFUSD, LFTMSG, WRGPRS
    expected_statuses = {
        'SVYCMP': {'name': 'Survey Complete', 'human': 'Y'},
        'REFUSD': {'name': 'Refused Participation', 'human': 'Y'},
        'LFTMSG': {'name': 'Left Message', 'human': 'N'},
        'WRGPRS': {'name': 'Wrong Person', 'human': 'Y'}
    }
    
    found_statuses = {s['status']: s for s in statuses}
    
    status_score = 0
    for code, criteria in expected_statuses.items():
        if code in found_statuses:
            status_score += 5
            s_data = found_statuses[code]
            # Optional: Strict check on flags, but existence is primary
            if s_data.get('human_answered') != criteria['human']:
                feedback_parts.append(f"Status {code} wrong Human Answered flag")
        else:
            feedback_parts.append(f"Missing status {code}")
            
    score += status_score
    if status_score == 20:
        feedback_parts.append("All custom statuses created")

    # --- Criterion 3: Script (20 pts) ---
    if script and script.get('id') == 'SENPOLLSC':
        score += 10
        feedback_parts.append("Script SENPOLLSC created")
        
        text = script.get('text', '').lower()
        keywords = ["national policy research", "constituent"]
        found_keywords = sum(1 for k in keywords if k in text)
        
        if found_keywords == len(keywords):
            score += 10
            feedback_parts.append("Script text verified")
        elif found_keywords > 0:
            score += 5
            feedback_parts.append("Script text partially verified")
        else:
            feedback_parts.append("Script text missing keywords")
    else:
        feedback_parts.append("Script SENPOLLSC NOT found")

    # --- Criterion 4: Assignments (20 pts) ---
    # List Assignment
    if list_info and list_info.get('campaign_id') == 'SENPOLL':
        score += 15
        feedback_parts.append("List 9001 assigned to SENPOLL")
    else:
        actual_list_camp = list_info.get('campaign_id') if list_info else "None"
        feedback_parts.append(f"List 9001 not assigned (Current: {actual_list_camp})")

    # Script Assignment
    if campaign and campaign.get('script') == 'SENPOLLSC':
        score += 5
        feedback_parts.append("Script assigned to Campaign")
    else:
        feedback_parts.append("Script not assigned to Campaign")

    # --- Result ---
    # Threshold 60
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }