#!/usr/bin/env python3
"""
Verifier for noc_custom_alarm_view_segregation task.

Scoring (100 pts total, pass threshold 50):
  Criterion 1: "Network-Core-Critical" view exists (25 pts)
  Criterion 2: "Network-Core-Critical" view has correct filters (25 pts)
  Criterion 3: "SysAdmin-Infrastructure-Alerts" view exists (25 pts)
  Criterion 4: "SysAdmin-Infrastructure-Alerts" view has correct filters (25 pts)
"""

import json
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_view_and_criteria(data, view_name, criteria_sets):
    """
    Search for the view_name and corresponding criteria in the collected DB and API data.
    Uses proximity windowing for robust matching.
    """
    db_raw = data.get("db_raw", "").lower()
    api_str = json.dumps(data.get("api_responses", {})).lower()
    
    combined = db_raw + " " + api_str
    
    name_found = view_name.lower() in combined
    criteria_met = False
    
    if name_found:
        # Check window around the name
        idx = combined.find(view_name.lower())
        window = combined[max(0, idx - 4000):min(len(combined), idx + 4000)]
        
        # Check if any criteria set is fully met in the window
        for cset in criteria_sets:
            if all(kw.lower() in window for kw in cset):
                criteria_met = True
                break
                
        # Fallback: Check if criteria exist anywhere in the combined text (loose match)
        if not criteria_met:
            for cset in criteria_sets:
                if all(kw.lower() in combined for kw in cset):
                    criteria_met = True
                    break
                    
    return name_found, criteria_met


def verify_noc_custom_alarm_view_segregation(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/alarm_view_result.json")
    local_path = "/tmp/alarm_view_verify_result.json"
    
    try:
        copy_from_env(result_file, local_path)
        with open(local_path, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result file: {e}. Check export_result.sh execution."
        }
        
    score = 0
    feedback = []
    
    # -------------------------------------------------------------------------
    # 1. Network Team View Checks
    # -------------------------------------------------------------------------
    net_name = metadata.get("network_view_name", "Network-Core-Critical")
    net_criteria = [
        ["critical", "router", "switch"],
        ["critical", "network"]  # Fallback in case they grouped it as a general network category
    ]
    
    net_found, net_crit_met = find_view_and_criteria(data, net_name, net_criteria)
    
    if net_found:
        score += 25
        feedback.append(f"PASS: Found view '{net_name}' (+25)")
        if net_crit_met:
            score += 25
            feedback.append(f"PASS: Criteria (Severity & Category) for '{net_name}' met (+25)")
        else:
            feedback.append(f"FAIL: Criteria (Severity & Category) for '{net_name}' not met (0/25)")
    else:
        feedback.append(f"FAIL: View '{net_name}' not found (0/50)")
        
    # -------------------------------------------------------------------------
    # 2. SysAdmin Team View Checks
    # -------------------------------------------------------------------------
    sys_name = metadata.get("sysadmin_view_name", "SysAdmin-Infrastructure-Alerts")
    sys_criteria = [
        ["critical", "trouble", "server", "storage"],
        ["critical", "trouble", "windows", "storage"],
        ["critical", "trouble", "linux", "storage"],
        ["critical", "trouble", "server"] # Generous fallback
    ]
    
    sys_found, sys_crit_met = find_view_and_criteria(data, sys_name, sys_criteria)
    
    if sys_found:
        score += 25
        feedback.append(f"PASS: Found view '{sys_name}' (+25)")
        if sys_crit_met:
            score += 25
            feedback.append(f"PASS: Criteria (Severity & Category) for '{sys_name}' met (+25)")
        else:
            feedback.append(f"FAIL: Criteria (Severity & Category) for '{sys_name}' not met (0/25)")
    else:
        feedback.append(f"FAIL: View '{sys_name}' not found (0/50)")
        
    # -------------------------------------------------------------------------
    # Final Result
    # -------------------------------------------------------------------------
    passed = score >= 50
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }