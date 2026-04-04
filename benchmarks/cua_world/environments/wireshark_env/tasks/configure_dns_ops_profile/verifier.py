#!/usr/bin/env python3
"""
Verifier for configure_dns_ops_profile task.
Checks:
1. Profile 'DNS_Ops' exists.
2. Preferences contain custom columns (TransID, Query) and exclude 'Length'.
3. Coloring rules contain 'DNS_Fail' with correct filter.
4. Screenshot evidence exists.
"""

import json
import tempfile
import os
import re

def verify_configure_dns_ops_profile(traj, env_info, task_info):
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
    
    # Metadata requirements
    req_cols = task_info.get('metadata', {}).get('required_columns', [])
    forbidden_cols = task_info.get('metadata', {}).get('forbidden_columns', [])
    req_rule = task_info.get('metadata', {}).get('coloring_rule', {})

    # 1. Profile Existence (20 pts)
    if result.get('profile_exists'):
        score += 20
        feedback_parts.append("Profile 'DNS_Ops' created")
    else:
        feedback_parts.append("Profile 'DNS_Ops' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Check Columns in Preferences (50 pts total)
    prefs_content = result.get('prefs_content', '')
    
    # Check for 'Length' removal (10 pts)
    # The format string looks like: "Length", "%L"
    if any(col in prefs_content for col in forbidden_cols):
        feedback_parts.append("'Length' column still present")
    else:
        score += 10
        feedback_parts.append("'Length' column removed")

    # Check for 'TransID' (20 pts)
    # Look for the field name 'dns.id' in the preferences string
    # Format usually: "Title", "%Cus:dns.id:0:R"
    if 'dns.id' in prefs_content:
        score += 20
        feedback_parts.append("'TransID' column added")
    else:
        feedback_parts.append("Missing 'TransID' column (dns.id)")

    # Check for 'Query' (20 pts)
    # Look for field name 'dns.qry.name'
    if 'dns.qry.name' in prefs_content:
        score += 20
        feedback_parts.append("'Query' column added")
    else:
        feedback_parts.append("Missing 'Query' column (dns.qry.name)")

    # 3. Check Coloring Rules (20 pts)
    rules_content = result.get('rules_content', '')
    rule_name = req_rule.get('name', 'DNS_Fail')
    rule_filter = req_rule.get('filter', 'dns.flags.rcode != 0')
    
    # Format: @Name@Filter@[bg][fg]
    # Simple check: does the string contain the name and filter?
    # We remove spaces from filter to make check robust against whitespace differences
    clean_rules = rules_content.replace(" ", "")
    clean_filter = rule_filter.replace(" ", "")
    
    if rule_name in rules_content and clean_filter in clean_rules:
        score += 20
        feedback_parts.append(f"Coloring rule '{rule_name}' configured correctly")
    elif rule_name in rules_content:
        score += 10
        feedback_parts.append(f"Coloring rule '{rule_name}' found but filter mismatch")
    else:
        feedback_parts.append(f"Coloring rule '{rule_name}' missing")

    # 4. Screenshot Evidence (10 pts)
    if result.get('screenshot_exists'):
        score += 10
        feedback_parts.append("Screenshot saved")
    else:
        feedback_parts.append("Screenshot missing")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }