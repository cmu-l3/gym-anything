#!/usr/bin/env python3
"""
verifier.py — Automated Network Discovery Profile Configuration

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Floor-1-Core-Network profile exists (15 pts) + IP range configured (10 pts) + Credential exists (8 pts) = 33 pts
  Criterion 2: Floor-2-Office-Network profile exists (15 pts) + IP range configured (10 pts) + Credential exists (8 pts) = 33 pts
  Criterion 3: Floor-3-Lab-Network profile exists (15 pts) + IP range configured (10 pts) + Credential exists (9 pts) = 34 pts
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _find_in_text(text, query):
    if not text:
        return False
    return query.lower() in text.lower()

def _check_profile_with_range(text, profile_name, ip_range):
    """
    Check if profile name exists, and if IP range exists in the data.
    Uses a proximity window to help ensure the IP range belongs to the profile,
    but falls back to a global search since IP ranges like '10.1.1' are unique to this task.
    """
    text_lower = text.lower()
    name_lower = profile_name.lower()
    ip_lower = ip_range.lower()
    
    idx = text_lower.find(name_lower)
    if idx == -1:
        return False, False
        
    # Check within a generous window of the profile name
    window_start = max(0, idx - 4000)
    window_end = min(len(text_lower), idx + len(name_lower) + 4000)
    window = text_lower[window_start:window_end]
    
    ip_found = ip_lower in window
    
    # Fallback to global search if not found in window (may be in a separate table)
    if not ip_found:
        ip_found = ip_lower in text_lower
        
    return True, ip_found

def verify_network_discovery_profile_config(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/discovery_profile_result.json")
    local_path = "/tmp/discovery_profile_verify_result.json"

    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Ensure export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}
        
    db_raw = data.get("db_raw", "")
    combined_json = json.dumps({
        "d1": data.get("discovery_api_1"),
        "d2": data.get("discovery_api_2"),
        "c1": data.get("cred_api_1"),
        "c2": data.get("cred_api_2"),
    })
    
    # Combine DB text and API JSON text into a single searchable body
    combined_text = (db_raw + " " + combined_json).lower()
    
    score = 0
    feedback = []
    
    profiles = task_info.get("metadata", {}).get("profiles", [])
    
    # Default fallback profiles if metadata missing
    if not profiles:
        profiles = [
            {"name": "Floor-1-Core-Network", "ip_range": "10.1.1", "community": "floor1-monitor"},
            {"name": "Floor-2-Office-Network", "ip_range": "10.1.2", "community": "floor2-monitor"},
            {"name": "Floor-3-Lab-Network", "ip_range": "10.1.3", "community": "floor3-monitor"}
        ]
    
    for p in profiles:
        name = p["name"]
        ip = p["ip_range"]
        community = p["community"]
        
        name_found, ip_found = _check_profile_with_range(combined_text, name, ip)
        comm_found = _find_in_text(combined_text, community)
        
        # Profile Name Criteria (15 pts)
        if name_found:
            score += 15
            feedback.append(f"PASS: Profile '{name}' found (+15)")
        else:
            feedback.append(f"FAIL: Profile '{name}' NOT found (0/15)")
            
        # IP Range Criteria (10 pts)
        if ip_found:
            score += 10
            feedback.append(f"PASS: IP range containing '{ip}' found (+10)")
        else:
            feedback.append(f"FAIL: IP range containing '{ip}' NOT found (0/10)")
            
        # Credential Criteria (8 or 9 pts depending on profile to equal 100 total)
        if name == "Floor-3-Lab-Network":
            if comm_found:
                score += 9
                feedback.append(f"PASS: Credential '{community}' found (+9)")
            else:
                feedback.append(f"FAIL: Credential '{community}' NOT found (0/9)")
        else:
            if comm_found:
                score += 8
                feedback.append(f"PASS: Credential '{community}' found (+8)")
            else:
                feedback.append(f"FAIL: Credential '{community}' NOT found (0/8)")
                
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }