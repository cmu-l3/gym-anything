#!/usr/bin/env python3
"""Verifier for ssh_username_exposure_audit task.

Checks:
1. Report exists with the exact required name.
2. Query targets `security_logs`.
3. Query uses `len()` function.
4. Query filters for length > 15.
5. Strict privacy compliance: dynamic execution output has NO `user` or `_raw` field, but DOES have `src_ip` and `count`.
"""

import json, tempfile, os, re, logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ssh_username_exposure_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/ssh_username_exposure_result.json", tmp.name)
        with open(tmp.name) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name): os.unlink(tmp.name)

    analysis = data.get('analysis', {})
    found_report = analysis.get('found_report', False)
    search_query = analysis.get('search_query', '')
    
    score = 0
    feedback = []
    privacy_passed = False
    
    if found_report:
        score += 20
        feedback.append("Report 'SSH_Username_Exposure_Audit' exists.")
    else:
        feedback.append("FAIL: Report 'SSH_Username_Exposure_Audit' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
        
    search_lower = search_query.lower()
    
    # Check index
    if 'security_logs' in search_lower:
        score += 15
        feedback.append("Query targets 'security_logs'.")
    else:
        feedback.append("FAIL: Query does not target 'security_logs'.")
        
    # Check len()
    if 'len(' in search_lower:
        score += 20
        feedback.append("Query uses 'len()' function.")
    else:
        feedback.append("FAIL: Query does not use 'len()' function.")
        
    # Check threshold > 15
    if re.search(r'>\s*15', search_lower) or re.search(r'>=\s*16', search_lower):
        score += 15
        feedback.append("Query filters for lengths > 15.")
    else:
        feedback.append("FAIL: Query does not appear to filter for lengths > 15.")
        
    # Check privacy compliance
    execution_success = analysis.get('execution_success', False)
    sample_events = analysis.get('sample_events', [])
    
    if not execution_success:
        feedback.append("FAIL: Search failed to execute dynamically, cannot verify output compliance.")
    elif len(sample_events) == 0:
        # If it returns 0 events, it might be correct but no anomalies found >15.
        # Let's inspect the SPL query for table or stats projection.
        has_table = re.search(r'\|\s*table\s+', search_lower)
        has_stats = re.search(r'\|\s*stats\s+', search_lower)
        
        if has_table or has_stats:
            has_table_user = re.search(r'\|\s*table\s+.*user', search_lower)
            if has_table_user:
                 feedback.append("CRITICAL PRIVACY FAILURE: 'table' command explicitly includes 'user' field.")
            else:
                 score += 30
                 privacy_passed = True
                 feedback.append("Privacy compliance met: Search uses valid projection/redaction (0 events returned, verified statically).")
        else:
            feedback.append("FAIL: 0 events returned and no explicit 'table' or 'stats' found in query.")
    else:
        # Check first event
        event = sample_events[0]
        keys = set([k.lower() for k in event.keys() if not k.startswith('_') or k == '_raw']) # Ignore internal __ keys, keep _raw
        
        has_user = 'user' in keys
        has_raw = '_raw' in keys
        has_src_ip = 'src_ip' in keys
        has_count = any('count' in k for k in keys) or 'c' in keys
        
        if has_user or has_raw:
            feedback.append(f"CRITICAL PRIVACY FAILURE: Result table contains sensitive fields ('user': {has_user}, '_raw': {has_raw}).")
        elif not has_src_ip:
            feedback.append(f"FAIL: Result table missing 'src_ip'. Found fields: {list(keys)}")
        elif not has_count:
            feedback.append(f"FAIL: Result table missing 'count' field. Found fields: {list(keys)}")
        elif len(keys) > 5:
            # Stats output should have very few columns
            feedback.append(f"FAIL: Result table contains too many fields ({len(keys)}), expecting strict projection.")
        else:
            score += 30
            privacy_passed = True
            feedback.append(f"Privacy compliance met: Output cleanly redacted. Found fields: {list(keys)}")
            
    passed = score >= 70 and privacy_passed
    
    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback)
    }