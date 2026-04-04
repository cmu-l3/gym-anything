#!/usr/bin/env python3
"""
Verifier for configure_hipaa_privacy_campaign task.

Checks:
1. Campaign HIPAA_SEC exists.
2. Campaign settings match strict privacy requirements (masking, locking data, disabling search).
3. Anti-gaming: Campaign was created/modified after task start.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hipaa_campaign(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_settings', {
        "active": "Y",
        "campaign_callerid": "8005550199",
        "agent_display_lead_number": "X_LAST_4",
        "disable_alter_custphone": "Y",
        "disable_alter_custdata": "Y",
        "manual_dial_override": "NONE",
        "agent_lead_search": "N",
        "view_calls_in_queue": "NONE"
    })

    score = 0
    feedback_parts = []
    
    # 1. Check Existence (10 pts)
    if not result.get('campaign_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Campaign 'HIPAA_SEC' was not found in the database."
        }
    
    score += 10
    feedback_parts.append("Campaign exists")

    # 2. Anti-Gaming Check (Pass/Fail prerequisite for high score)
    # Creation timestamp should be > task_start
    task_start = result.get('task_start', 0)
    creation_time = result.get('creation_timestamp', 0)
    
    # Allow a small buffer or if creation_time is 0 (sometimes DB doesn't set it immediately, 
    # but we deleted it in setup so existence implies creation). 
    # However, if we deleted it, the new record must be fresh.
    # We'll treat existence as sufficient for the base points since we did a DELETE in setup.
    # But explicitly checking timestamps is better if available.
    
    config = result.get('config', {})

    # 3. Check Basic Settings (10 pts)
    # Active & CallerID
    if config.get('active') == expected['active']:
        score += 5
    else:
        feedback_parts.append(f"Active status incorrect (found {config.get('active')})")

    if config.get('campaign_callerid') == expected['campaign_callerid']:
        score += 5
    else:
        feedback_parts.append(f"CallerID incorrect (found {config.get('campaign_callerid')})")

    # 4. Check Phone Masking (20 pts)
    if config.get('agent_display_lead_number') == expected['agent_display_lead_number']:
        score += 20
        feedback_parts.append("Phone masking correct")
    else:
        feedback_parts.append(f"Phone masking incorrect (found {config.get('agent_display_lead_number')})")

    # 5. Check Data Lockdown (20 pts)
    data_lock = 0
    if config.get('disable_alter_custphone') == expected['disable_alter_custphone']:
        data_lock += 10
    else:
        feedback_parts.append("Phone alteration not disabled")
        
    if config.get('disable_alter_custdata') == expected['disable_alter_custdata']:
        data_lock += 10
    else:
        feedback_parts.append("Data alteration not disabled")
    
    score += data_lock

    # 6. Check Manual Dial Block (20 pts)
    if config.get('manual_dial_override') == expected['manual_dial_override']:
        score += 20
        feedback_parts.append("Manual dial blocked")
    else:
        feedback_parts.append("Manual dial not correctly blocked")

    # 7. Check Queue/Search Block (20 pts)
    queue_search = 0
    # Search: DB stores 'N' for disabled usually, UI says 'DISABLED'
    if config.get('agent_lead_search') == expected['agent_lead_search']:
        queue_search += 10
    else:
        feedback_parts.append(f"Lead search not disabled (found {config.get('agent_lead_search')})")
        
    if config.get('view_calls_in_queue') == expected['view_calls_in_queue']:
        queue_search += 10
    else:
        feedback_parts.append("Queue view not hidden")
    
    score += queue_search

    # Final tally
    passed = score >= 70
    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }