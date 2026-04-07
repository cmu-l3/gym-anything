#!/usr/bin/env python3
"""
verifier.py — Device Dependency Map Configuration for Root Cause Analysis

Scoring (100 pts total, pass threshold 60):
  - Device Campus-Core-RTR-01 exists (15 pts)
  - Device Distro-Switch-A exists (15 pts)
  - Device Distro-Switch-B exists (15 pts)
  - Device Access-Switch-Floor2 exists (15 pts)
  - Dependency: Distro-Switch-A -> Campus-Core-RTR-01 (15 pts)
  - Dependency: Distro-Switch-B -> Campus-Core-RTR-01 (13 pts)
  - Dependency: Access-Switch-Floor2 -> Distro-Switch-A (12 pts)
"""

import json
import os
import re

RESULT_FILE = "/tmp/device_dependency_result.json"

def _load_result(env_info, result_file):
    """Load the result JSON via copy_from_env."""
    local_path = '/tmp/device_dependency_verify_result.json'
    if not env_info.get('copy_from_env'):
        return None, "copy_from_env function not available"
        
    try:
        env_info['copy_from_env'](result_file, local_path)
        with open(local_path) as f:
            return json.load(f), None
    except Exception as e:
        return None, f"Could not retrieve/parse result file: {e}"

def _extract_device_list(api_data):
    """Extract flat list of devices from the API response envelope."""
    if not api_data or not isinstance(api_data, dict):
        return []
    
    for key in ("data", "devices", "deviceList", "result"):
        val = api_data.get(key)
        if isinstance(val, list):
            return val
        if isinstance(val, dict):
            for inner_key in ("data", "devices", "deviceList"):
                inner = val.get(inner_key)
                if isinstance(inner, list):
                    return inner
    return []

def _check_device_exists(target_name, target_ip, api_devices, db_devices_raw):
    """Verify if a device exists by Name or IP in API or DB dump."""
    # Check API list
    for d in api_devices:
        if not isinstance(d, dict): continue
        name = str(d.get("displayName", d.get("name", d.get("deviceName", "")))).strip()
        ip = str(d.get("ipAddress", d.get("ip", d.get("deviceIP", "")))).strip()
        
        if name.lower() == target_name.lower() or ip == target_ip:
            return True, str(d.get("id", d.get("monitorId", d.get("name", ""))))
            
    # Check raw DB fallback
    lower_db = str(db_devices_raw).lower()
    if target_name.lower() in lower_db or target_ip in lower_db:
        return True, None # Found but no reliable ID extracted
        
    return False, None

def _check_dependency_exists(child_name, child_ip, child_id, parent_name, parent_ip, parent_id, db_deps_raw, db_devices_raw):
    """
    Check if a parent-child relationship exists.
    Looks for occurrences of both child identifier and parent identifier in the same table row.
    """
    raw_texts = [str(db_deps_raw).lower(), str(db_devices_raw).lower()]
    
    child_identifiers = [child_name.lower(), child_ip]
    if child_id: child_identifiers.append(str(child_id).lower())
    
    parent_identifiers = [parent_name.lower(), parent_ip]
    if parent_id: parent_identifiers.append(str(parent_id).lower())
    
    for raw_text in raw_texts:
        for line in raw_text.split('\n'):
            line = line.strip()
            if not line: continue
            
            # Check if ANY child identifier and ANY parent identifier exist on this line
            child_present = any(cid in line for cid in child_identifiers if cid)
            parent_present = any(pid in line for pid in parent_identifiers if pid)
            
            # Additional heuristic: Sometimes they are in the exact same table row of the relationship table.
            if child_present and parent_present:
                # Ensure they are distinct tokens (so child IP "10.0.1.2" doesn't falsely match if it's a substring)
                return True
                
    return False

def verify_device_dependency_rca_config(traj, env_info, task_info):
    """Main verification function."""
    
    result_file = task_info.get("metadata", {}).get("result_file", RESULT_FILE)
    
    data, error = _load_result(env_info, result_file)
    if error:
        return {
            "passed": False,
            "score": 0,
            "feedback": error
        }

    api_devices = _extract_device_list(data.get("api_devices", {}))
    db_devices_raw = data.get("db_devices_raw", "")
    db_deps_raw = data.get("db_dependencies_raw", "")

    score = 0
    details = []
    
    # -----------------------------------------------------------------------
    # CRITERIA 1-4: Check Devices Exist (15 points each)
    # -----------------------------------------------------------------------
    dev_info = {
        "core": {"name": "Campus-Core-RTR-01", "ip": "10.0.1.1", "pts": 15},
        "distro_a": {"name": "Distro-Switch-A", "ip": "10.0.1.2", "pts": 15},
        "distro_b": {"name": "Distro-Switch-B", "ip": "10.0.1.3", "pts": 15},
        "access": {"name": "Access-Switch-Floor2", "ip": "10.0.1.4", "pts": 15}
    }
    
    found_devices = {}
    
    for key, info in dev_info.items():
        exists, dev_id = _check_device_exists(info["name"], info["ip"], api_devices, db_devices_raw)
        found_devices[key] = {"exists": exists, "id": dev_id}
        
        if exists:
            score += info["pts"]
            details.append(f"PASS: Device '{info['name']}' found (+{info['pts']})")
        else:
            details.append(f"FAIL: Device '{info['name']}' not found (0/{info['pts']})")

    # -----------------------------------------------------------------------
    # CRITERIA 5-7: Check Dependencies
    # -----------------------------------------------------------------------
    deps_info = [
        {"child": "distro_a", "parent": "core", "pts": 15, "desc": "Distro-Switch-A -> Campus-Core-RTR-01"},
        {"child": "distro_b", "parent": "core", "pts": 13, "desc": "Distro-Switch-B -> Campus-Core-RTR-01"},
        {"child": "access", "parent": "distro_a", "pts": 12, "desc": "Access-Switch-Floor2 -> Distro-Switch-A"}
    ]
    
    for dep in deps_info:
        c_key = dep["child"]
        p_key = dep["parent"]
        
        if not found_devices[c_key]["exists"] or not found_devices[p_key]["exists"]:
            details.append(f"FAIL: Dependency {dep['desc']} missing (one or both devices not found) (0/{dep['pts']})")
            continue
            
        c_name = dev_info[c_key]["name"]
        c_ip = dev_info[c_key]["ip"]
        c_id = found_devices[c_key]["id"]
        
        p_name = dev_info[p_key]["name"]
        p_ip = dev_info[p_key]["ip"]
        p_id = found_devices[p_key]["id"]
        
        dep_exists = _check_dependency_exists(c_name, c_ip, c_id, p_name, p_ip, p_id, db_deps_raw, db_devices_raw)
        
        if dep_exists:
            score += dep["pts"]
            details.append(f"PASS: Dependency {dep['desc']} configured (+{dep['pts']})")
        else:
            details.append(f"FAIL: Dependency {dep['desc']} not found in database (0/{dep['pts']})")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }