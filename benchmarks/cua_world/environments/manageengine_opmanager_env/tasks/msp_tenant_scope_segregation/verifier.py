#!/usr/bin/env python3
"""
verifier.py — MSP Tenant Scope Segregation

Scoring (100 pts total, pass threshold 65):
  Criterion 1: Business View 'Globex-Infrastructure' exists (25 pts)
  Criterion 2: Device '127.0.0.1' is assigned to Business View (15 pts)
  Criterion 3: User 'globex_noc' exists (25 pts)
  Criterion 4: Scope restriction connects 'globex_noc' to 'Globex-Infrastructure' (35 pts)
"""

import json
import os


RESULT_FILE = "/tmp/msp_tenant_result.json"
PASS_THRESHOLD = 65


def _extract_list(api_data):
    """Safely extract a list of dicts from an API response envelope."""
    if not api_data:
        return []
    if isinstance(api_data, list):
        # Handle cases where multiple JSON objects were concatenated into a list
        res = []
        for item in api_data:
            res.extend(_extract_list(item))
        return res
    if isinstance(api_data, dict):
        for key in ("data", "users", "businessViews", "maps", "result", "response", "message"):
            val = api_data.get(key)
            if isinstance(val, list):
                return val
            if isinstance(val, dict):
                for inner_key in ("data", "users", "businessViews", "maps"):
                    inner = val.get(inner_key)
                    if isinstance(inner, list):
                        return inner
    return []


def _proximity_check(text, term1, term2, window=1000):
    """Check if term2 appears within `window` characters of term1 in text."""
    t = text.lower()
    t1 = term1.lower()
    t2 = term2.lower()
    
    idx1 = t.find(t1)
    if idx1 == -1:
        return False
        
    start = max(0, idx1 - window)
    end = min(len(t), idx1 + len(t1) + window)
    
    return t2 in t[start:end]


def verify_msp_tenant_scope_segregation(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', RESULT_FILE)
    local_path = '/tmp/msp_tenant_verify_result.json'

    # Copy result file from environment
    if env_info and 'copy_from_env' in env_info:
        try:
            env_info['copy_from_env'](result_file, local_path)
            with open(local_path) as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file '{result_file}': {e}",
            }
    else:
        try:
            if os.path.exists(RESULT_FILE):
                with open(RESULT_FILE) as f:
                    result_data = json.load(f)
            else:
                result_data = {}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load local results: {e}"}

    users_list = _extract_list(result_data.get("users_api", {}))
    bvs_list = _extract_list(result_data.get("business_views_api", {}))
    db_raw = result_data.get("db_raw_dump", "")

    expected_bv = "Globex-Infrastructure"
    expected_ip = "127.0.0.1"
    expected_user = "globex_noc"

    score = 0
    details = []

    # ---------------------------------------------------------------------------
    # Criterion 1: Business View 'Globex-Infrastructure' exists (25 pts)
    # ---------------------------------------------------------------------------
    bv_exists = False
    
    # Check API
    for bv in bvs_list:
        if isinstance(bv, dict) and bv.get("name", "").lower() == expected_bv.lower():
            bv_exists = True
            break
            
    # Check DB
    if not bv_exists and expected_bv.lower() in db_raw.lower():
        bv_exists = True
        
    if bv_exists:
        score += 25
        details.append(f"PASS: Business View '{expected_bv}' found (+25)")
    else:
        details.append(f"FAIL: Business View '{expected_bv}' not found (0/25)")

    # ---------------------------------------------------------------------------
    # Criterion 2: Device '127.0.0.1' assigned to BV (15 pts)
    # ---------------------------------------------------------------------------
    device_assigned = False
    if bv_exists:
        # Check API: usually the device/IP string will be nested in the BV dictionary
        for bv in bvs_list:
            if isinstance(bv, dict) and bv.get("name", "").lower() == expected_bv.lower():
                if expected_ip in json.dumps(bv):
                    device_assigned = True
                    break
        
        # Fallback: Proximity check in DB dump
        if not device_assigned and _proximity_check(db_raw, expected_bv, expected_ip, window=1500):
            device_assigned = True
            
        if device_assigned:
            score += 15
            details.append(f"PASS: Device '{expected_ip}' associated with Business View (+15)")
        else:
            details.append(f"FAIL: Device '{expected_ip}' not associated with Business View (0/15)")
    else:
        details.append("FAIL: Cannot verify device assignment because Business View is missing (0/15)")

    # ---------------------------------------------------------------------------
    # Criterion 3: User 'globex_noc' exists (25 pts)
    # ---------------------------------------------------------------------------
    user_exists = False
    
    # Check API
    for u in users_list:
        if isinstance(u, dict) and u.get("userName", "").lower() == expected_user.lower():
            user_exists = True
            break
            
    # Check DB
    if not user_exists and expected_user.lower() in db_raw.lower():
        user_exists = True
        
    if user_exists:
        score += 25
        details.append(f"PASS: User '{expected_user}' found (+25)")
    else:
        details.append(f"FAIL: User '{expected_user}' not found (0/25)")

    # ---------------------------------------------------------------------------
    # Criterion 4: Scope restriction limits 'globex_noc' to 'Globex-Infrastructure' (35 pts)
    # ---------------------------------------------------------------------------
    scope_restricted = False
    if user_exists and bv_exists:
        # First check API - look for the BV name in the User's dictionary
        for u in users_list:
            if isinstance(u, dict) and u.get("userName", "").lower() == expected_user.lower():
                # Some API returns have "scope": ["Globex-Infrastructure"] or "businessViews" keys
                u_str = json.dumps(u).lower()
                if expected_bv.lower() in u_str:
                    scope_restricted = True
                    break
        
        # Fallback check DB - Scope mapping tables (proximity check between username and BV name)
        if not scope_restricted and _proximity_check(db_raw, expected_user, expected_bv, window=2000):
            scope_restricted = True
            
        if scope_restricted:
            score += 35
            details.append("PASS: Scope restriction links User to Business View (+35)")
        else:
            details.append("FAIL: Scope restriction not found linking User to Business View (0/35)")
    else:
        details.append("FAIL: Cannot verify scope restriction because User or Business View is missing (0/35)")

    passed = score >= PASS_THRESHOLD

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }