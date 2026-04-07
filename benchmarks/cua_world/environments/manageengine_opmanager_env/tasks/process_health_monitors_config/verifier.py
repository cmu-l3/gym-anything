#!/usr/bin/env python3
"""
verifier.py — Process Health Monitors Config

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Device '127.0.0.1' exists in inventory (10 pts)
  Criterion 2: Process monitor 'postgres' exists (18 pts)
  Criterion 3: Process monitor 'java' exists (18 pts)
  Criterion 4: Process monitor 'snmpd' exists (18 pts)
  Criterion 5: Process monitor 'cron' exists (18 pts)
  Criterion 6: Process monitor 'sshd' exists (18 pts)

Anti-gaming verification:
  We count the occurrences of the exact word boundary for each process name 
  in the final database dump versus the initial database dump. If the count 
  has increased, the monitor was added. We also check API responses as an 
  alternative valid signal.
"""

import json
import os
import re
import sys
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_FILE = "/tmp/process_health_result.json"

def _extract_devices(api_data):
    """Flatten OpManager device list from API response."""
    if not api_data or not isinstance(api_data, dict):
        return []
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

def _device_ip(d):
    if not isinstance(d, dict):
        return ""
    return str(d.get("ipAddress") or d.get("ip") or d.get("deviceIP") or d.get("hostName") or "").strip()

def _device_name(d):
    if not isinstance(d, dict):
        return ""
    return str(d.get("displayName") or d.get("name") or d.get("deviceName") or "").strip()

def _count_occurrences(text, target):
    """Count exact word boundary occurrences of target (case-insensitive)."""
    if not text:
        return 0
    pattern = r'\b' + re.escape(target) + r'\b'
    return len(re.findall(pattern, text, re.IGNORECASE))

def verify_process_health_monitors_config(traj, env_info, task_info):
    """Main verification logic."""
    local_path = '/tmp/process_health_verify_result.json'

    # Copy result file from environment
    if env_info and 'copy_from_env' in env_info:
        result_file = (task_info or {}).get('metadata', {}).get('result_file', RESULT_FILE)
        try:
            env_info['copy_from_env'](result_file, local_path)
            with open(local_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran successfully."
            }
    else:
        # Fallback for local testing
        if not os.path.exists(RESULT_FILE):
            return {"passed": False, "score": 0, "feedback": "Result file not found."}
        try:
            with open(RESULT_FILE) as f:
                data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse JSON: {e}"}

    score = 0
    details = []

    # Unpack Data
    devices_api = data.get("devices_api", {})
    proc_api_raw = str(data.get("process_monitors_api_raw", "")).lower()
    init_db_raw = str(data.get("initial_db_raw", ""))
    final_db_raw = str(data.get("final_db_raw", ""))

    devices = _extract_devices(devices_api)

    # -----------------------------------------------------------------------
    # Criterion 1: Device 127.0.0.1 exists in inventory (10 pts)
    # -----------------------------------------------------------------------
    device_found = False
    for d in devices:
        if _device_ip(d) == "127.0.0.1" or "localhost" in _device_name(d).lower():
            device_found = True
            break
    
    # Check if we can find it in the DB dump as a fallback
    if not device_found and "127.0.0.1" in final_db_raw:
        device_found = True

    if device_found:
        score += 10
        details.append("PASS: Device '127.0.0.1' exists in inventory (+10)")
    else:
        details.append("FAIL: Device '127.0.0.1' not found in inventory (0/10)")

    # -----------------------------------------------------------------------
    # Criteria 2-6: Process Monitors
    # -----------------------------------------------------------------------
    processes = ["postgres", "java", "snmpd", "cron", "sshd"]
    points_per_process = 18

    for proc in processes:
        init_count = _count_occurrences(init_db_raw, proc)
        final_count = _count_occurrences(final_db_raw, proc)
        api_count = _count_occurrences(proc_api_raw, proc)

        # It's a pass if the DB count increased (new monitor added) 
        # OR if it's explicitly found in the API response (which represents current state)
        if final_count > init_count or api_count > 0:
            score += points_per_process
            details.append(f"PASS: Process monitor '{proc}' successfully configured (+{points_per_process})")
        else:
            details.append(f"FAIL: Process monitor '{proc}' not found or unchanged (0/{points_per_process})")

    # Final tally
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }