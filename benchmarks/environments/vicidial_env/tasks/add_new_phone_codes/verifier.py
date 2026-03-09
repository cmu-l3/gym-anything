#!/usr/bin/env python3
"""
Verifier for Add New Phone Codes task.

Criteria:
1. Records exist in DB (20 pts each)
2. Records match CSV data exactly (10 pts each)
3. Anti-gaming: Admin log shows 'ADD' events via UI (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_new_phone_codes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_data = metadata.get('expected_data', {
        '324': {'cc': '1', 'gmt': '-5.00', 'dst': 'Y', 'state': 'FL', 'desc': 'Jacksonville Overlay'},
        '729': {'cc': '1', 'gmt': '-5.00', 'dst': 'Y', 'state': 'TN', 'desc': 'Chattanooga Overlay'},
        '839': {'cc': '1', 'gmt': '-5.00', 'dst': 'Y', 'state': 'SC', 'desc': 'Columbia Overlay'}
    })
    
    # Load result from container
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
            
    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Error in export script: {result['error']}"}

    score = 0
    feedback_parts = []
    
    found_records = result.get('records', {})
    
    # Check each area code
    for ac, expected in expected_data.items():
        if ac in found_records:
            # Existence check (20 pts)
            score += 20
            feedback_parts.append(f"Area code {ac}: Found (+20)")
            
            # Accuracy check (10 pts)
            actual = found_records[ac]
            errors = []
            
            # Helper to normalize strings for comparison
            def norm(s): return str(s).strip()
            
            if norm(actual.get('cc')) != norm(expected['cc']): 
                errors.append(f"CountryCode {actual.get('cc')}!={expected['cc']}")
            if norm(actual.get('gmt')) != norm(expected['gmt']): 
                errors.append(f"GMT {actual.get('gmt')}!={expected['gmt']}")
            if norm(actual.get('dst')) != norm(expected['dst']): 
                errors.append(f"DST {actual.get('dst')}!={expected['dst']}")
            if norm(actual.get('state')) != norm(expected['state']): 
                errors.append(f"State {actual.get('state')}!={expected['state']}")
            if norm(actual.get('desc')) != norm(expected['desc']): 
                errors.append(f"Desc '{actual.get('desc')}'!='{expected['desc']}'")
                
            if not errors:
                score += 10
                feedback_parts.append(f"Area code {ac}: Data matches exactly (+10)")
            else:
                feedback_parts.append(f"Area code {ac} errors: {', '.join(errors)}")
        else:
            feedback_parts.append(f"Area code {ac}: MISSING")

    # Anti-gaming check (10 pts)
    log_count = result.get('admin_log_add_count', 0)
    if log_count > 0:
        score += 10
        feedback_parts.append(f"Admin log confirms UI usage ({log_count} events) (+10)")
    else:
        feedback_parts.append("WARNING: No Admin Log events found. Did you use the web interface?")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }