#!/usr/bin/env python3
"""
verifier.py — FIPS Compliant SNMPv3 Credential Migration

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Core-Network-v3 profile exists with all fields — 34 pts
  Criterion 2: Edge-Firewall-v3 profile exists with all fields — 33 pts
  Criterion 3: DMZ-Services-v3 profile exists with all fields — 33 pts
"""

import json
import os

RESULT_FILE = "/tmp/snmpv3_migration_result.json"

def _check_profile_fields(text, required_fields):
    text_lower = text.lower()
    for field in required_fields:
        if field.lower() not in text_lower:
            return False, field
    return True, None

def verify_fips_compliant_snmpv3_credential_migration(traj, env_info, task_info):
    result_file = task_info.get('metadata', {}).get('result_file', RESULT_FILE)
    local_path = '/tmp/snmpv3_migration_verify_result.json'

    # Retrieve the export data safely via copy_from_env
    if env_info and 'copy_from_env' in env_info:
        try:
            env_info['copy_from_env'](result_file, local_path)
            with open(local_path) as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}. Make sure export_result.sh was executed.",
            }
    else:
        try:
            with open(RESULT_FILE) as f:
                result_data = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Result file is missing or empty."}

    cred_api = result_data.get("credentials_api", {})
    cred_db_raw = result_data.get("credentials_db_raw", "")
    
    # Combine API data and DB raw dumps for a comprehensive search
    combined_text = json.dumps(cred_api) + "\n" + cred_db_raw

    score = 0
    details = []

    # Profile 1: Core-Network-v3
    core_fields = [
        "Core-Network-v3", 
        "core-sec-admin", 
        "core-ctx", 
        "CoreAuthSecure123!", 
        "CorePrivSecure123!"
    ]
    ok, missing = _check_profile_fields(combined_text, core_fields)
    if ok:
        score += 34
        details.append("PASS: Core-Network-v3 profile configured correctly (+34)")
    else:
        details.append(f"FAIL: Core-Network-v3 missing field: {missing} (0/34)")

    # Profile 2: Edge-Firewall-v3
    edge_fields = [
        "Edge-Firewall-v3", 
        "edge-sec-admin", 
        "edge-ctx", 
        "EdgeAuthSecure123!", 
        "EdgePrivSecure123!"
    ]
    ok, missing = _check_profile_fields(combined_text, edge_fields)
    if ok:
        score += 33
        details.append("PASS: Edge-Firewall-v3 profile configured correctly (+33)")
    else:
        details.append(f"FAIL: Edge-Firewall-v3 missing field: {missing} (0/33)")

    # Profile 3: DMZ-Services-v3
    dmz_fields = [
        "DMZ-Services-v3", 
        "dmz-sec-admin", 
        "dmz-ctx", 
        "DmzAuthSecure123!", 
        "DmzPrivSecure123!"
    ]
    ok, missing = _check_profile_fields(combined_text, dmz_fields)
    if ok:
        score += 33
        details.append("PASS: DMZ-Services-v3 profile configured correctly (+33)")
    else:
        details.append(f"FAIL: DMZ-Services-v3 missing field: {missing} (0/33)")

    # Apply anti-gaming check: Ensure we actually see SNMPv3 version markers in text
    if score > 0 and "v3" not in combined_text.lower():
        score = score // 2
        details.append("WARNING: Profiles detected but no SNMPv3 version markers found. Deducting points.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(details)
    }