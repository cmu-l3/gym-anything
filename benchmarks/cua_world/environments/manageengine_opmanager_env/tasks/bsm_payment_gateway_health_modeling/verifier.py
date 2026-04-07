#!/usr/bin/env python3
"""
verifier.py — BSM Payment Gateway Health Modeling

Scoring (100 pts total, pass threshold 70):
  Criterion 1: Device 'Payment-Web-01' (10.50.1.10) exists — 15 pts
  Criterion 2: Device 'Payment-Web-02' (10.50.1.11) exists — 15 pts
  Criterion 3: Device 'Payment-App-Core' (10.50.2.10) exists — 15 pts
  Criterion 4: Device 'Payment-DB-Cluster' (10.50.3.10) exists — 15 pts
  Criterion 5: Business Service 'Payment-Processing-Gateway' exists — 40 pts
"""

import json
import os


def _extract_devices(api_data):
    """Extract a flat list of device dicts from various OpManager API envelope shapes."""
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


def _device_exists(devices_api, devices_db_raw, target_name, target_ip):
    """Check if a device exists by name or IP in either the API response or DB dump."""
    target_name_lower = target_name.lower()
    
    # Check API
    for d in devices_api:
        name = str(d.get("displayName") or d.get("name") or d.get("deviceName") or "").strip().lower()
        ip = str(d.get("ipAddress") or d.get("ip") or d.get("deviceIP") or d.get("hostName") or "").strip()
        if name == target_name_lower or ip == target_ip:
            return True

    # Check DB
    if devices_db_raw:
        db_lower = devices_db_raw.lower()
        if target_name_lower in db_lower or target_ip in db_lower:
            return True

    return False


def _bsm_exists(bsm_api, bsm_db_raw, target_bsm_name):
    """Check if the Business Service exists in the API response or BSM-specific DB tables."""
    target_lower = target_bsm_name.lower()

    # Check API JSON response
    if bsm_api:
        api_text = json.dumps(bsm_api).lower()
        if target_lower in api_text:
            return True

    # Check DB raw text (Filtered during export to only BSM specific tables)
    if bsm_db_raw:
        if target_lower in bsm_db_raw.lower():
            return True

    return False


def verify_bsm_payment_gateway_health_modeling(traj, env_info, task_info):
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/bsm_result.json")
    expected_devices = metadata.get("expected_devices", [
        {"name": "Payment-Web-01", "ip": "10.50.1.10"},
        {"name": "Payment-Web-02", "ip": "10.50.1.11"},
        {"name": "Payment-App-Core", "ip": "10.50.2.10"},
        {"name": "Payment-DB-Cluster", "ip": "10.50.3.10"}
    ])
    expected_bsm_name = metadata.get("expected_bsm_name", "Payment-Processing-Gateway")
    
    local_path = "/tmp/bsm_verify_result.json"

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        copy_from_env(result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file '{result_file}': {e}. Ensure export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    devices_api = _extract_devices(data.get("devices_api", {}))
    devices_db_raw = data.get("devices_db_raw", "")
    bsm_api = data.get("bsm_api", {})
    bsm_db_raw = data.get("bsm_db_raw", "")

    score = 0
    details = []

    # Check the 4 devices
    for dev in expected_devices:
        name = dev["name"]
        ip = dev["ip"]
        if _device_exists(devices_api, devices_db_raw, name, ip):
            score += 15
            details.append(f"PASS: Device '{name}' ({ip}) found (+15)")
        else:
            details.append(f"FAIL: Device '{name}' ({ip}) not found (0/15)")

    # Check the Business Service
    if _bsm_exists(bsm_api, bsm_db_raw, expected_bsm_name):
        score += 40
        details.append(f"PASS: Business Service '{expected_bsm_name}' found (+40)")
    else:
        details.append(f"FAIL: Business Service '{expected_bsm_name}' not found (0/40)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }