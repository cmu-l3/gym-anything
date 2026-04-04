#!/usr/bin/env python3
"""
Verifier for configure_manual_preview_campaign task.

Checks:
1. Campaign VIP_DIAL configuration (Manual, Preview, etc.)
2. List 9500 population (at least 50 leads)
3. Data mapping correctness (Custom headers -> Vicidial fields)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_manual_preview_campaign(traj, env_info, task_info):
    """
    Verify campaign configuration and lead import mapping.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
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
    
    # 1. Verify Campaign Config
    campaign = result.get('campaign_config', {})
    if not campaign:
        campaign = {} # handle empty/null
        
    # Dial Method: MANUAL (15 pts)
    dial_method = campaign.get('dial_method', 'RATIO')
    if dial_method == 'MANUAL':
        score += 15
        feedback_parts.append("Campaign Dial Method correct (MANUAL)")
    else:
        feedback_parts.append(f"Campaign Dial Method incorrect ({dial_method})")

    # Manual Dial Preview: YES (20 pts)
    # Vicidial stores 'Y' or 'YES' depending on version/field, usually 'Y' in DB for checkboxes or 'YES' for dropdowns.
    # We accept Y or YES.
    preview = campaign.get('manual_dial_preview', 'N')
    if preview in ['Y', 'YES', '1']:
        score += 20
        feedback_parts.append("Preview dialing enabled")
    else:
        feedback_parts.append(f"Preview dialing disabled ({preview})")

    # List Order: DOWN COUNT (5 pts)
    order = campaign.get('lead_order', '')
    if order == 'DOWN COUNT':
        score += 5
        feedback_parts.append("Lead order correct")
    else:
        feedback_parts.append(f"Lead order incorrect ({order})")
        
    # Active: Y (5 pts)
    active = campaign.get('active', 'N')
    if active == 'Y':
        score += 5
        feedback_parts.append("Campaign is active")
    else:
        feedback_parts.append("Campaign is inactive")
        
    # Auto Alt Dial: NONE (5 pts)
    alt_dial = campaign.get('auto_alt_dial', '')
    if alt_dial == 'NONE':
        score += 5
        feedback_parts.append("Auto Alt Dial correct")
    else:
        feedback_parts.append(f"Auto Alt Dial incorrect ({alt_dial})")

    # 2. Verify List Data
    list_count = int(result.get('list_count', 0))
    if list_count >= 50:
        score += 15
        feedback_parts.append(f"Leads loaded successfully ({list_count})")
    elif list_count > 0:
        score += 5
        feedback_parts.append(f"Some leads loaded ({list_count}), but fewer than expected")
    else:
        feedback_parts.append("No leads found in list 9500")

    # 3. Verify Mapping (35 pts total)
    # We check the sample row to see if data landed in the right columns
    sample = result.get('sample_row', {})
    if not sample:
        sample = {}

    # Map 'Official_Name' -> 'First Name'
    # The name in CSV is "First Last". If mapped to First Name, the whole string appears there.
    first_name = sample.get('first_name', '')
    if len(first_name) > 2 and " " in first_name: 
        # Heuristic: if it contains a space, it likely contains the full name as requested
        score += 10
        feedback_parts.append("Name mapping correct")
    elif len(first_name) > 1:
        # Partial credit if they mapped it but maybe split it
        score += 5
        feedback_parts.append("Name mapping partial")
    else:
        feedback_parts.append("Name mapping failed or empty")

    # Map 'Gov_ID' -> 'Vendor Lead Code'
    # Our setup script generates IDs like 'SEN-1000'
    vendor_code = sample.get('vendor_lead_code', '')
    if 'SEN-' in vendor_code:
        score += 10
        feedback_parts.append("Vendor Lead Code mapping correct")
    else:
        feedback_parts.append(f"Vendor Lead Code mapping failed ('{vendor_code}')")

    # Map 'Contact_Number' -> 'Phone'
    phone = sample.get('phone_number', '')
    if len(phone) >= 10:
        score += 10
        feedback_parts.append("Phone mapping correct")
    else:
        feedback_parts.append("Phone mapping failed")

    # Map 'Home_State' -> 'State'
    state = sample.get('state', '')
    if len(state) == 2:
        score += 5
        feedback_parts.append("State mapping correct")
    else:
        feedback_parts.append("State mapping failed")

    # Final check
    # Pass threshold: 70 points.
    # Must have Campaign Method MANUAL (15) and Preview (20) and Leads Loaded (15) = 50 baseline
    # + Mapping points to pass.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }