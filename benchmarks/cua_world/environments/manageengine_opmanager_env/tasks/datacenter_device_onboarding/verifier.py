#!/usr/bin/env python3
"""
verifier.py — Datacenter Device Onboarding

Scoring (100 pts total, pass threshold 60):
  The agent must successfully onboard 5 specific devices.
  Each correctly onboarded device is worth 20 points.
  A device is considered correct if EITHER its expected exact name OR exact IP
  appears in the API device list or raw Database output.
"""

import json
import os
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Default devices to check if metadata is missing
EXPECTED_DEVICES = [
    {"name": "DC2-Core-Switch-01", "ip": "10.200.1.1"},
    {"name": "DC2-Core-Switch-02", "ip": "10.200.1.2"},
    {"name": "DC2-Distribution-FW", "ip": "10.200.2.1"},
    {"name": "DC2-Storage-Array-01", "ip": "10.200.3.10"},
    {"name": "DC2-Hypervisor-Node-01", "ip": "10.200.4.1"}
]

def _extract_flat_devices(api_data):
    """
    Extract a flat list of device dictionaries from OpManager's API envelope.
    """
    if not api_data or not isinstance(api_data, dict):
        return []
    
    # Common envelope keys
    for key in ("data", "devices", "deviceList", "result", "response"):
        val = api_data.get(key)
        if isinstance(val, list):
            return val
        if isinstance(val, dict):
            for inner_key in ("data", "devices", "deviceList"):
                inner = val.get(inner_key)
                if isinstance(inner, list):
                    return inner
                    
    if isinstance(api_data, list):
        return api_data
    return []

def _check_device_exists(expected_dev, api_devices, db_raw):
    """
    Check if a specific device is present in the API list or Database dump.
    Returns (bool, str) -> (found, message)
    """
    target_name = expected_dev["name"].lower()
    target_ip = expected_dev["ip"].lower()
    
    # 1. Check API
    for d in api_devices:
        if not isinstance(d, dict):
            continue
            
        api_name = str(d.get("displayName") or d.get("name") or d.get("deviceName") or "").lower().strip()
        api_ip = str(d.get("ipAddress") or d.get("ip") or d.get("deviceIP") or d.get("hostName") or "").lower().strip()
        
        if api_name == target_name or api_ip == target_ip:
            return True, f"Found via API: name='{api_name}', IP='{api_ip}'"
            
    # 2. Check DB
    lower_db = db_raw.lower()
    if target_name in lower_db:
        return True, f"Found via DB search (Name match: {target_name})"
    if target_ip in lower_db:
        return True, f"Found via DB search (IP match: {target_ip})"
        
    return False, f"Not found in API or DB (Name: {target_name}, IP: {target_ip})"

def verify_datacenter_device_onboarding(traj, env_info, task_info):
    """
    Main verifier entry point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in env_info."}
        
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/dc2_onboarding_result.json")
    expected_devices = metadata.get("devices", EXPECTED_DEVICES)
    
    local_path = "/tmp/dc2_onboarding_verify_result.json"
    
    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from container: {e}. Ensure export_result.sh executed."
        }
        
    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse the JSON result file: {e}"
        }
        
    api_devices = _extract_flat_devices(data.get("devices_api", {}))
    db_raw = str(data.get("devices_db_raw", ""))
    
    score = 0
    max_score = len(expected_devices) * 20
    details = []
    
    # Verify each expected device
    for dev in expected_devices:
        found, msg = _check_device_exists(dev, api_devices, db_raw)
        if found:
            score += 20
            details.append(f"PASS: Device {dev['name']} onboarded successfully (+20). {msg}")
        else:
            details.append(f"FAIL: Device {dev['name']} missing (0/20). {msg}")
            
    passed = score >= 60  # Pass threshold = 60 (at least 3/5 devices)
    
    feedback = " | ".join(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }