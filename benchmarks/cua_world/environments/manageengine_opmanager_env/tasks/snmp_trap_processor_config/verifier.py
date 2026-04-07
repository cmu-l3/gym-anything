#!/usr/bin/env python3
"""
verifier.py — SNMP Trap Processor Config

Scoring (100 pts total, pass threshold 50):
  Criterion 1: LinkDown-Critical-Trap exists with OID containing 1.3.6.1.6.3.1.1.5.3 (25 pts)
  Criterion 2: LinkUp-Recovery-Trap exists with OID containing 1.3.6.1.6.3.1.1.5.4 (25 pts)
  Criterion 3: AuthFailure-Security-Trap exists with OID containing 1.3.6.1.6.3.1.1.5.5 (25 pts)
  Criterion 4: ColdStart-Device-Trap exists with OID containing 1.3.6.1.6.3.1.1.5.1 (25 pts)
"""

import json
import os
import re

RESULT_FILE = "/tmp/trap_processor_result.json"

def _check_trap_presence(db_raw, api_data, expected_name, expected_oid):
    """
    Check if a given trap processor name and its expected OID appear together.
    We check both the API response (if structured properly) and the raw DB text.
    """
    # 1. Search DB Text
    if db_raw:
        db_text_lower = db_raw.lower()
        if expected_name.lower() in db_text_lower and expected_oid.lower() in db_text_lower:
            # Simple substring proximity check. Often names and OIDs are in the same DB row.
            return True, "Found in DB raw data"
            
    # 2. Search API Data
    if api_data:
        api_text_lower = json.dumps(api_data).lower()
        if expected_name.lower() in api_text_lower and expected_oid.lower() in api_text_lower:
            return True, "Found in API response"

    return False, f"Not found"

def verify_snmp_trap_processor_config(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', RESULT_FILE)
    local_path = '/tmp/trap_verify_result.json'

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Ensure export_result.sh completed successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    api_data = data.get("trap_processors_api", {})
    db_raw = data.get("trap_processors_db_raw", "")

    score = 0
    details = []

    # Expected processors
    processors = [
        {"name": "LinkDown-Critical-Trap", "oid": "1.3.6.1.6.3.1.1.5.3"},
        {"name": "LinkUp-Recovery-Trap", "oid": "1.3.6.1.6.3.1.1.5.4"},
        {"name": "AuthFailure-Security-Trap", "oid": "1.3.6.1.6.3.1.1.5.5"},
        {"name": "ColdStart-Device-Trap", "oid": "1.3.6.1.6.3.1.1.5.1"}
    ]

    for p in processors:
        found, msg = _check_trap_presence(db_raw, api_data, p["name"], p["oid"])
        if found:
            score += 25
            details.append(f"PASS: Trap '{p['name']}' with OID {p['oid']} found (+25).")
        else:
            details.append(f"FAIL: Trap '{p['name']}' or OID {p['oid']} not found (0/25).")

    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }