#!/usr/bin/env python3
"""
Verifier for clone_adapt_campaign_settings task.

Criteria:
1. Campaign SEN_WEST exists.
2. Campaign is Active (Y).
3. Campaign Name is 'Senate Polling West'.
4. Campaign CallerID is '3105550199'.
5. Manual Dial Prefix is '9'.
6. CRITICAL: Inherited settings must match source SENPOLL (Dial Method, Timeout, Drop, Level, VM).
7. Anti-gaming: Created/Modified after task start.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_clone_adapt_campaign_settings(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata requirements
    metadata = task_info.get('metadata', {})
    req_id = metadata.get('required_id', 'SEN_WEST')
    req_name = metadata.get('required_name', 'Senate Polling West')
    req_cid = metadata.get('required_cid', '3105550199')
    req_prefix = metadata.get('required_prefix', '9')
    expected_settings = metadata.get('expected_settings', {})

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

    # Extract DB data
    db_result = result.get('db_result', {})
    exists = db_result.get('exists', False)
    data = db_result.get('data', {})

    feedback_parts = []
    score = 0
    
    # 1. Existence Check (10 pts)
    if not exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Campaign {req_id} was not found in the database."
        }
    score += 10
    feedback_parts.append(f"Campaign {req_id} exists")

    # 2. Identity Check (Name & Active) (10 pts)
    name_match = (data.get('campaign_name') == req_name)
    active_match = (data.get('active') == 'Y')
    
    if name_match:
        score += 5
        feedback_parts.append("Name correct")
    else:
        feedback_parts.append(f"Name incorrect (Got: {data.get('campaign_name')})")

    if active_match:
        score += 5
        feedback_parts.append("Active status correct")
    else:
        feedback_parts.append(f"Active status incorrect (Got: {data.get('active')})")

    # 3. New Config Check (CallerID & Prefix) (30 pts)
    cid_match = (data.get('campaign_cid') == req_cid)
    prefix_match = (data.get('manual_dial_prefix') == req_prefix)

    if cid_match:
        score += 15
        feedback_parts.append("CallerID correct")
    else:
        feedback_parts.append(f"CallerID incorrect (Got: {data.get('campaign_cid')})")

    if prefix_match:
        score += 15
        feedback_parts.append("Dial Prefix correct")
    else:
        feedback_parts.append(f"Dial Prefix incorrect (Got: {data.get('manual_dial_prefix')})")

    # 4. Complex Settings Inheritance (50 pts)
    # These verify the user actually cloned the campaign or was extremely meticulous
    inheritance_score = 0
    inheritance_items = []
    
    # Map db fields to expected keys
    # DB: dial_method, auto_dial_level, dial_timeout, drop_call_seconds, voicemail_ext
    
    checks = [
        ('dial_method', expected_settings.get('dial_method'), 10),
        ('auto_dial_level', expected_settings.get('auto_dial_level'), 10),
        ('dial_timeout', expected_settings.get('dial_timeout'), 10),
        ('drop_call_seconds', expected_settings.get('drop_call_seconds'), 10),
        ('voicemail_ext', expected_settings.get('voicemail_ext'), 10)
    ]

    for field, expected, pts in checks:
        # Convert both to string for comparison to avoid float mismatch
        actual = str(data.get(field, ''))
        expected = str(expected)
        
        # Handle simple float formatting diffs (e.g. 1.25 vs 1.250)
        try:
            if float(actual) == float(expected):
                inheritance_score += pts
                continue
        except ValueError:
            pass
            
        if actual == expected:
            inheritance_score += pts
        else:
            inheritance_items.append(f"{field} mismatch (Exp: {expected}, Got: {actual})")

    score += inheritance_score
    if inheritance_score == 50:
        feedback_parts.append("All inherited settings match source")
    elif inheritance_score > 0:
        feedback_parts.append(f"Partial inheritance match ({inheritance_score}/50)")
        feedback_parts.extend(inheritance_items)
    else:
        feedback_parts.append("Inherited settings do not match source (Did you clone?)")
        feedback_parts.extend(inheritance_items)

    # Final Pass Determination
    # Must have created the campaign with correct new configs AND at least attempted to keep settings
    passed = (exists and cid_match and prefix_match and inheritance_score >= 30)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }