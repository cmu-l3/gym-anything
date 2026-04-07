#!/usr/bin/env python3
"""
verifier.py — SIEM Syslog Forwarding Profile Configuration

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Profile Name 'SOC-SIEM-Forwarder' exists                    — 20 pts
  Criterion 2: Destination Host '10.50.100.10' and Port '514'              — 20 pts
  Criterion 3: Syslog Facility 'local7' (or Local 7)                       — 20 pts
  Criterion 4: Alarm Criteria includes Critical & Trouble                  — 20 pts
  Criterion 5: Custom payload format 'OpManagerAlert | $displayName...'    — 20 pts

Anti-gaming: The profile name and IP address must be present in the actual DB/API dump.
"""

import json
import os
import re
import sys

RESULT_FILE = "/tmp/siem_syslog_result.json"

def _load_result(env_info, result_file):
    """Load the result JSON using copy_from_env."""
    local_path = '/tmp/siem_syslog_verify_result.json'
    try:
        env_info['copy_from_env'](result_file, local_path)
        with open(local_path) as f:
            return json.load(f)
    except Exception as e:
        return None

def verify_siem_syslog_forwarding_profile_config(traj=None, env_info=None, task_info=None):
    if not env_info or 'copy_from_env' not in env_info:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = (task_info or {}).get('metadata', {})
    result_file = metadata.get('result_file', RESULT_FILE)
    
    result_data = _load_result(env_info, result_file)
    if not result_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve or parse result file: {result_file}"
        }

    db_raw = result_data.get("syslog_profiles_db_raw", "")
    api_data = result_data.get("notification_profiles_api", {})

    # Combine sources into a single searchable lowercase string
    combined_text = (db_raw + "\n" + json.dumps(api_data)).lower()
    
    score = 0
    details = []

    # Criterion 1: Profile Name
    profile_name = "soc-siem-forwarder"
    profile_exists = profile_name in combined_text
    
    if profile_exists:
        score += 20
        details.append("PASS: Profile 'SOC-SIEM-Forwarder' found (+20)")
    else:
        details.append("FAIL: Profile 'SOC-SIEM-Forwarder' not found (0/20)")

    # If the profile doesn't exist at all, return early (prevent partial matches from other configs)
    if not profile_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(details)
        }

    # Extract the block of text around the profile name to isolate parameters
    # Find the index of the profile name, take a ~2000 char window around it
    idx = combined_text.find(profile_name)
    start_idx = max(0, idx - 1000)
    end_idx = min(len(combined_text), idx + 2000)
    window_text = combined_text[start_idx:end_idx]

    # Criterion 2: Destination Host and Port
    host_found = "10.50.100.10" in window_text
    port_found = "514" in window_text
    
    if host_found and port_found:
        score += 20
        details.append("PASS: Destination IP '10.50.100.10' and port '514' found (+20)")
    elif host_found:
        score += 10
        details.append("PARTIAL: Destination IP found, but port '514' missing (+10)")
    else:
        details.append("FAIL: Destination IP '10.50.100.10' not found (0/20)")

    # Criterion 3: Syslog Facility
    # Can be represented as 'local7', 'local 7', or an enum value in DB (often just 'local7' in OpManager)
    if "local7" in window_text or "local 7" in window_text:
        score += 20
        details.append("PASS: Facility 'local7' found (+20)")
    else:
        details.append("FAIL: Facility 'local7' not found in profile configuration (0/20)")

    # Criterion 4: Alarm Criteria (Critical & Trouble)
    # OpManager typically stores criteria as string severity or integers. We look for the text equivalents.
    crit_found = "critical" in window_text
    trouble_found = "trouble" in window_text
    
    if crit_found and trouble_found:
        score += 20
        details.append("PASS: Alarm criteria 'Critical' and 'Trouble' found (+20)")
    elif crit_found or trouble_found:
        score += 10
        details.append("PARTIAL: Only one alarm criteria (Critical or Trouble) found (+10)")
    else:
        details.append("FAIL: Alarm criteria 'Critical' and 'Trouble' not found (0/20)")

    # Criterion 5: Custom payload format
    # Check for the static parts of the string 'OpManagerAlert | $displayName | $stringSeverity | $message'
    # Variables might be represented differently, so we check for 'opmanageralert' and 'severity'
    if "opmanageralert" in window_text and "severity" in window_text:
        score += 20
        details.append("PASS: Custom payload format 'OpManagerAlert' found (+20)")
    else:
        details.append("FAIL: Custom payload format not found in profile configuration (0/20)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }