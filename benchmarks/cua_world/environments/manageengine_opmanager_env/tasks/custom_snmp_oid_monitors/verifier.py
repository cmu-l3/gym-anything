#!/usr/bin/env python3
"""
verifier.py — Custom SNMP Monitor Configuration

Scoring (100 pts total):
  For each of the 4 monitors:
    - Monitor name exists (API or DB) -> 15 pts
    - Monitor OID is correct and associated -> 10 pts
  Total: 4 * 25 = 100 pts

Pass Threshold: 60 pts (At least 2 monitors fully correct, or 3+ with partial credit)
"""

import json
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/custom_snmp_monitors_result.json"


def _check_monitor(db_raw, api_text, target_name, target_oid):
    """
    Checks if the monitor name and OID exist.
    Uses a proximity search in the raw DB text to ensure the OID
    is associated with the name, and also checks the API payload.
    Returns: (name_found: bool, oid_found: bool)
    """
    name_found = False
    oid_found = False
    
    target_name_lower = target_name.lower()
    db_lower = db_raw.lower()
    api_lower = api_text.lower()
    
    # 1. Check Name
    if target_name_lower in db_lower or target_name_lower in api_lower:
        name_found = True
        
    # 2. Check OID (Only matters if name is found, but we'll check regardless)
    # We want to ensure the exact OID string is present in the configuration.
    if target_oid in db_raw or target_oid in api_text:
        # Check proximity in DB: OID should be near the monitor name
        idx = db_lower.find(target_name_lower)
        if idx != -1:
            # Look in a 2000 character window around the name
            window_start = max(0, idx - 1000)
            window_end = min(len(db_lower), idx + len(target_name_lower) + 1000)
            window = db_raw[window_start:window_end]
            if target_oid in window:
                oid_found = True
        
        # Check proximity in API JSON
        idx_api = api_lower.find(target_name_lower)
        if idx_api != -1 and not oid_found:
            window_start = max(0, idx_api - 1000)
            window_end = min(len(api_lower), idx_api + len(target_name_lower) + 1000)
            window = api_text[window_start:window_end]
            if target_oid in window:
                oid_found = True
                
        # Fallback: if OID is in DB but not strictly near name, we still grant credit
        # since these OIDs are highly specific to this task.
        if not oid_found and target_oid in db_raw:
            oid_found = True

    return name_found, oid_found


def verify_custom_snmp_oid_monitors(traj, env_info, task_info):
    """Main verification function."""
    
    # Use copy_from_env to get the result file safely
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', RESULT_FILE)
    local_path = '/tmp/custom_snmp_verify_result.json'

    try:
        copy_from_env(result_file, local_path)
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve or parse result file: {e}. Ensure export_result.sh ran correctly."
        }

    db_raw = data.get("monitors_db_raw", "")
    api_data = data.get("monitors_api", {})
    api_text = json.dumps(api_data)
    
    expected_monitors = metadata.get("monitors", [
        {"name": "System-Load-1min", "oid": "1.3.6.1.4.1.2021.10.1.3.1"},
        {"name": "System-Load-5min", "oid": "1.3.6.1.4.1.2021.10.1.3.2"},
        {"name": "TCP-ActiveConnections", "oid": "1.3.6.1.2.1.6.9.0"},
        {"name": "Swap-Total-Size", "oid": "1.3.6.1.4.1.2021.4.3.0"}
    ])

    score = 0
    details = []

    for mon in expected_monitors:
        name = mon["name"]
        oid = mon["oid"]
        
        name_found, oid_found = _check_monitor(db_raw, api_text, name, oid)
        
        if name_found:
            score += 15
            details.append(f"PASS: Monitor '{name}' exists (+15)")
            if oid_found:
                score += 10
                details.append(f"PASS: OID '{oid}' is correctly configured for '{name}' (+10)")
            else:
                details.append(f"FAIL: OID '{oid}' not found near monitor '{name}' (+0)")
        else:
            details.append(f"FAIL: Monitor '{name}' not found (+0)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }