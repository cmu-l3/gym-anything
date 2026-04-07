#!/usr/bin/env python3
"""
Verifier for configure_campaign_trackers task in SuiteCRM.

VERIFICATION STRATEGY:
1. Verify database record for the new parent Campaign ("Industrial Sensor Launch 2026").
2. Validate the fields (Type, Status, Budget, Expected Revenue).
3. Verify presence of all three expected Tracker child records linked to the Campaign.
4. Anti-gaming check: Ensure records have `created_by` = '1' (meaning created via the web app as admin, not direct SQL)
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def clean_financial(val):
    """Parse floats/ints safely from potentially formatted CRM currency strings."""
    if not val:
        return 0.0
    val_str = str(val).replace('$', '').replace(',', '').strip()
    try:
        return float(val_str)
    except ValueError:
        return 0.0

def verify_configure_campaign_trackers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_type = metadata.get('expected_type', 'Web')
    expected_status = metadata.get('expected_status', 'Active')
    expected_budget = float(metadata.get('expected_budget', 15000))
    expected_revenue = float(metadata.get('expected_revenue', 75000))
    expected_trackers = metadata.get('expected_trackers', {})

    # Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_campaign_trackers_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Anti-Gaming Check
    # -------------------------------------------------------------------------
    campaign = result.get('campaign', {})
    trackers = result.get('trackers', [])
    
    # We expect creation via UI, mapping to the 'admin' user id ('1')
    if result.get('campaign_found'):
        if campaign.get('created_by') != '1':
            return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: Campaign not created by authenticated UI user"}

    # -------------------------------------------------------------------------
    # 2. Base Campaign Existence and Basics (30 Points)
    # -------------------------------------------------------------------------
    if not result.get('campaign_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Campaign 'Industrial Sensor Launch 2026' not found in database"
        }

    c_type = campaign.get('type', '')
    c_status = campaign.get('status', '')

    if c_type.lower() == expected_type.lower() and c_status.lower() == expected_status.lower():
        score += 30
        feedback_parts.append(f"Campaign Basics correct (Type: {c_type}, Status: {c_status}) [+30]")
    else:
        score += 15 # Partial credit for creating the record
        feedback_parts.append(f"Campaign created but basics mismatch. Expected {expected_type}/{expected_status}, Got {c_type}/{c_status} [+15]")

    # -------------------------------------------------------------------------
    # 3. Campaign Financial Metrics (10 Points)
    # -------------------------------------------------------------------------
    budget = clean_financial(campaign.get('budget'))
    revenue = clean_financial(campaign.get('expected_revenue'))
    
    # Using small tolerance for possible float inconsistencies
    if abs(budget - expected_budget) < 1.0 and abs(revenue - expected_revenue) < 1.0:
        score += 10
        feedback_parts.append("Financial Metrics correct [+10]")
    else:
        feedback_parts.append(f"Financial Metrics incorrect. Expected Budget: {expected_budget}, Revenue: {expected_revenue}. Got Budget: {budget}, Revenue: {revenue}")

    # -------------------------------------------------------------------------
    # 4. Tracker URLs (20 Points Each x 3 = 60 Points)
    # -------------------------------------------------------------------------
    tracker_map = {t['name'].lower().strip(): t['url'].strip() for t in trackers}
    
    for tracker_name, expected_url in expected_trackers.items():
        search_key = tracker_name.lower().strip()
        
        if search_key in tracker_map:
            actual_url = tracker_map[search_key]
            
            # Allow minor protocol/slash variance via regex (e.g. http vs https, trailing slash)
            expected_pattern = re.escape(expected_url).replace(r"https\:", r"https?\:")
            
            if re.search(expected_pattern, actual_url, re.IGNORECASE) or expected_url in actual_url:
                score += 20
                feedback_parts.append(f"Tracker '{tracker_name}' correct [+20]")
            else:
                score += 5 # Created, but wrong URL
                feedback_parts.append(f"Tracker '{tracker_name}' URL mismatch (Expected: {expected_url}, Got: {actual_url}) [+5]")
        else:
            feedback_parts.append(f"Tracker '{tracker_name}' missing")

    # Determine passing status: requires main campaign and at least 2 correct trackers (70/100 threshold)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "campaign_found": True,
            "trackers_count": len(trackers)
        }
    }