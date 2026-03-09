#!/usr/bin/env python3
"""
Verifier for consolidate_crm_tags@1

Tests:
1. Target opportunities have the official 'Urgent' tag.
2. Target opportunities DO NOT have 'urgent' or 'ASAP' tags.
3. 'urgent' and 'ASAP' tags are deleted from the system configuration.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_crm_tags(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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
    
    # Sanity Check
    if not result.get("app_running", False):
        return {"passed": False, "score": 0, "feedback": "Odoo was not accessible during verification"}

    tags_status = result.get("tags_status", {})
    opportunities = result.get("opportunities", {})
    
    target_opps = [
        'Emergency Generators - Apex Corp',
        'Rush Order - Beta Industries',
        'Expedited Shipping - Gamma Inc'
    ]
    
    # Scoring Breakdown:
    # 1. Tag Migration (45 points - 15 per opp)
    # 2. Bad Link Removal (30 points - 10 per opp)
    # 3. Configuration Cleanup (25 points - 12.5 per tag deleted)
    
    # 1. Check Tag Migration and Bad Link Removal
    migration_score = 0
    removal_score = 0
    
    for opp_name in target_opps:
        opp_data = opportunities.get(opp_name)
        
        if not opp_data:
            feedback_parts.append(f"Opportunity '{opp_name}' not found")
            continue
            
        # Check for 'Urgent' tag
        if opp_data.get("has_correct_tag"):
            migration_score += 15
            feedback_parts.append(f"✓ {opp_name}: Has 'Urgent'")
        else:
            feedback_parts.append(f"✗ {opp_name}: Missing 'Urgent'")
            
        # Check for bad tags
        if not opp_data.get("has_bad_tag"):
            removal_score += 10
        else:
            feedback_parts.append(f"✗ {opp_name}: Still has bad tags")

    score += migration_score
    score += removal_score
    
    # 2. Check Configuration Cleanup
    config_score = 0
    
    if tags_status.get("urgent_deleted"):
        config_score += 12.5
        feedback_parts.append("✓ 'urgent' tag deleted from system")
    else:
        feedback_parts.append("✗ 'urgent' tag still exists in system")
        
    if tags_status.get("ASAP_deleted"):
        config_score += 12.5
        feedback_parts.append("✓ 'ASAP' tag deleted from system")
    else:
        feedback_parts.append("✗ 'ASAP' tag still exists in system")
        
    score += int(config_score)
    
    # Round score
    score = min(100, score)
    
    pass_threshold = 85
    passed = score >= pass_threshold
    
    final_feedback = f"Score: {score}/{100}. " + " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }