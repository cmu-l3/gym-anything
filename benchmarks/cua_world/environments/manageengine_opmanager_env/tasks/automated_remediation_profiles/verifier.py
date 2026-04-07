#!/usr/bin/env python3
"""
Verifier for automated_remediation_profiles task.

Scoring (100 pts total, pass threshold 60):
  - Script 'restart_snmpd.sh' created, executable, correct content: 10 pts
  - Script 'clear_disk_cache.sh' created, executable, correct content: 10 pts
  - Script 'check_service_health.sh' created, executable, correct content: 10 pts
  
  - Profile 'Auto-Remediate-SNMP-Failure' exists: 20 pts
    - Maps to 'restart_snmpd.sh': +5 pts
  - Profile 'Auto-Remediate-Disk-Usage' exists: 15 pts
    - Maps to 'clear_disk_cache.sh': +5 pts
  - Profile 'Auto-Remediate-Device-Down' exists: 15 pts
    - Maps to 'check_service_health.sh': +5 pts
    
  - Playbook was read (timestamp change on playbook file): 5 pts
"""

import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _search_all(data: dict) -> str:
    """Return a single lower-cased string of everything in the DB/API result dict."""
    return json.dumps({
        "api": data.get("notification_profiles_api", {}),
        "db": data.get("notification_profiles_db_raw", "")
    }).lower()

def _check_profile_exists(combined_text: str, name: str) -> bool:
    """Check if the exact profile name (case-insensitive) appears in OpManager config."""
    return name.lower() in combined_text

def _check_profile_path(combined_text: str, name: str, path: str) -> bool:
    """Check if the script path is associated with the profile name within a text window."""
    lower_text = combined_text.lower()
    lower_name = name.lower()
    lower_path = path.lower()

    idx = lower_text.find(lower_name)
    if idx == -1:
        return False

    # Check within a 3000-character window (OpManager DB tables map actions via foreign keys, 
    # but the raw text dump generally puts related rows reasonably close in smaller labs, 
    # or the API json nests them directly)
    window_start = max(0, idx - 3000)
    window_end = min(len(lower_text), idx + len(lower_name) + 3000)
    window = lower_text[window_start:window_end]
    
    return lower_path in window

def verify_automated_remediation_profiles(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/automated_remediation_result.json")
    local_path = "/tmp/automated_remediation_verify_result.json"

    # 1. Retrieve the exported JSON result from the container
    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file '{result_file}': {e}. Ensure export_result.sh ran successfully."
        }

    # 2. Parse JSON
    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result file: {e}"
        }

    score = 0
    details = []
    
    scripts = data.get("scripts", {})
    combined_text = _search_all(data)

    # -----------------------------------------------------------------------
    # Criterion: Playbook Read (5 pts)
    # -----------------------------------------------------------------------
    if data.get("playbook_read", False):
        score += 5
        details.append("PASS: Playbook file was accessed/read (+5)")
    else:
        # Give benefit of doubt if they created the scripts perfectly
        s1 = scripts.get("restart_snmpd", {})
        s2 = scripts.get("clear_disk_cache", {})
        s3 = scripts.get("check_service_health", {})
        if s1.get("has_content") and s2.get("has_content") and s3.get("has_content"):
            score += 5
            details.append("PASS: Playbook read (inferred from correct script contents) (+5)")
        else:
            details.append("FAIL: No evidence playbook was read (0/5)")

    # -----------------------------------------------------------------------
    # Criterion: Scripts Created, Executable, Content (10 pts each = 30 pts)
    # -----------------------------------------------------------------------
    script_configs = [
        ("restart_snmpd", 10),
        ("clear_disk_cache", 10),
        ("check_service_health", 10)
    ]
    
    for script_key, max_pts in script_configs:
        s_data = scripts.get(script_key, {})
        if s_data.get("exists") and s_data.get("is_executable") and s_data.get("has_content") and s_data.get("created_during"):
            score += max_pts
            details.append(f"PASS: Script '{script_key}.sh' exists, is executable, and contains correct commands (+{max_pts})")
        else:
            if not s_data.get("exists"):
                details.append(f"FAIL: Script '{script_key}.sh' not found (0/{max_pts})")
            elif not s_data.get("is_executable"):
                details.append(f"FAIL: Script '{script_key}.sh' exists but is NOT executable (chmod +x) (0/{max_pts})")
            elif not s_data.get("has_content"):
                details.append(f"FAIL: Script '{script_key}.sh' exists but lacks required command content (0/{max_pts})")
            elif not s_data.get("created_during"):
                details.append(f"FAIL: Script '{script_key}.sh' exists but was not created during the task (anti-gaming) (0/{max_pts})")

    # -----------------------------------------------------------------------
    # Criterion: Profiles Exist and Path Mapped (65 pts total)
    # -----------------------------------------------------------------------
    profile_configs = [
        ("Auto-Remediate-SNMP-Failure", "restart_snmpd.sh", 20, 5),
        ("Auto-Remediate-Disk-Usage", "clear_disk_cache.sh", 15, 5),
        ("Auto-Remediate-Device-Down", "check_service_health.sh", 15, 5)
    ]

    for p_name, s_name, exist_pts, map_pts in profile_configs:
        if _check_profile_exists(combined_text, p_name):
            score += exist_pts
            details.append(f"PASS: Profile '{p_name}' found in OpManager (+{exist_pts})")
            
            # Check script mapping
            if _check_profile_path(combined_text, p_name, s_name):
                score += map_pts
                details.append(f"PASS: Profile '{p_name}' correctly maps to '{s_name}' (+{map_pts})")
            else:
                details.append(f"FAIL: Profile '{p_name}' does not map to correct script path '{s_name}' (0/{map_pts})")
        else:
            details.append(f"FAIL: Profile '{p_name}' not found in OpManager (0/{exist_pts + map_pts})")

    # Final pass determination
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details)
    }