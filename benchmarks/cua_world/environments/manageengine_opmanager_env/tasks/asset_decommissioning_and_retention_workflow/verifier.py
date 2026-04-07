#!/usr/bin/env python3
"""
verifier.py — Asset Decommissioning and Retention Workflow

Scoring (100 pts total, pass threshold 60):
  1. Group Created: 'Decommissioned-Assets' exists (20 pts)
  2. Retention Devices Unmanaged: old-db-server-01, old-db-server-02, legacy-archive-nas (20 pts)
  3. Retention Devices Grouped: The 3 devices belong to 'Decommissioned-Assets' (15 pts)
  4. Retired Devices Deleted: legacy-proxy-01, legacy-proxy-02 (25 pts)
  5. Decoy Devices Untouched: prod-db-server-01, prod-proxy-01 remain active (20 pts)
"""

import json
import os

RESULT_FILE = "/tmp/asset_decommission_result.json"

# Known IP mappings from setup
DEVICE_IPS = {
    "old-db-server-01": "127.0.0.11",
    "old-db-server-02": "127.0.0.12",
    "legacy-archive-nas": "127.0.0.13",
    "legacy-proxy-01": "127.0.0.14",
    "legacy-proxy-02": "127.0.0.15",
    "prod-db-server-01": "127.0.0.16",
    "prod-proxy-01": "127.0.0.17"
}

def _extract_api_devices(api_data):
    if not isinstance(api_data, dict):
        return []
    for key in ("data", "devices", "deviceList"):
        val = api_data.get(key)
        if isinstance(val, list):
            return val
    return []

def _check_group_exists(api_groups, db_cv):
    grp_name = "Decommissioned-Assets".lower()
    if grp_name in json.dumps(api_groups).lower():
        return True
    if grp_name in db_cv.lower():
        return True
    return False

def _is_deleted(db_mo, api_devices, display_name):
    # Should not be in DB
    for line in db_mo.split('\n'):
        parts = line.split('|')
        if len(parts) >= 1 and parts[0].strip().lower() == display_name.lower():
            return False
            
    # Should not be in API
    devices = _extract_api_devices(api_devices)
    for d in devices:
        name = str(d.get("displayName") or d.get("name") or "").strip().lower()
        if name == display_name.lower():
            return False
    return True

def _is_unmanaged(db_mo, api_devices, display_name):
    # Check DB (format: displayname | managed)
    for line in db_mo.split('\n'):
        parts = line.split('|')
        if len(parts) >= 2:
            if parts[0].strip().lower() == display_name.lower():
                val = parts[1].strip().lower()
                if val in ['f', 'false']:
                    return True
                    
    # Check API
    devices = _extract_api_devices(api_devices)
    for d in devices:
        name = str(d.get("displayName") or d.get("name") or "").strip().lower()
        if name == display_name.lower():
            is_managed = d.get("isManaged", True)
            managed_str = str(d.get("managed", "")).lower()
            if not is_managed or managed_str == "false":
                return True
    return False

def _is_managed(db_mo, api_devices, display_name):
    for line in db_mo.split('\n'):
        parts = line.split('|')
        if len(parts) >= 2:
            if parts[0].strip().lower() == display_name.lower():
                val = parts[1].strip().lower()
                if val in ['t', 'true']:
                    return True
                    
    devices = _extract_api_devices(api_devices)
    for d in devices:
        name = str(d.get("displayName") or d.get("name") or "").strip().lower()
        if name == display_name.lower():
            is_managed = d.get("isManaged", False)
            managed_str = str(d.get("managed", "")).lower()
            if is_managed or managed_str in ["true", ""]:
                return True
    return False

def _in_group(db_cvp, group_name, device_name):
    """Checks if the device is assigned to the group in CustomViewProps."""
    ip_address = DEVICE_IPS.get(device_name, "")
    for line in db_cvp.split('\n'):
        parts = line.split('|')
        if len(parts) >= 2:
            db_group = parts[0].strip().lower()
            db_entity = parts[1].strip().lower()
            if db_group == group_name.lower():
                # Entity could be the IP address or the display name
                if ip_address and ip_address.lower() in db_entity:
                    return True
                if device_name.lower() in db_entity:
                    return True
    return False

def verify_asset_decommissioning(traj, env_info, task_info):
    local_path = '/tmp/asset_decommission_verify_result.json'
    try:
        env_info['copy_from_env'](RESULT_FILE, local_path)
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    api_devices = data.get("api_devices", {})
    api_groups = data.get("api_groups", {})
    db_mo = data.get("db_managed_objects", "")
    db_cv = data.get("db_custom_view", "")
    db_cvp = data.get("db_custom_view_props", "")

    score = 0
    details = []

    # 1. Group Created (20 pts)
    if _check_group_exists(api_groups, db_cv):
        score += 20
        details.append("PASS: 'Decommissioned-Assets' group exists (+20)")
    else:
        details.append("FAIL: 'Decommissioned-Assets' group not found (0/20)")

    # 2. Retention Devices Unmanaged (20 pts total, ~6.6 per device)
    retention_devices = ["old-db-server-01", "old-db-server-02", "legacy-archive-nas"]
    unmanaged_count = 0
    for dev in retention_devices:
        if not _is_deleted(db_mo, api_devices, dev):
            if _is_unmanaged(db_mo, api_devices, dev):
                unmanaged_count += 1
                details.append(f"PASS: {dev} is unmanaged (+6.6)")
            else:
                details.append(f"FAIL: {dev} is not unmanaged")
        else:
            details.append(f"FAIL: {dev} was incorrectly deleted")
            
    score += int(unmanaged_count * 6.66)

    # 3. Retention Devices Grouped (15 pts total, 5 per device)
    grouped_count = 0
    for dev in retention_devices:
        if _in_group(db_cvp, "Decommissioned-Assets", dev):
            grouped_count += 1
            details.append(f"PASS: {dev} belongs to Decommissioned-Assets group (+5)")
        else:
            details.append(f"FAIL: {dev} is not in Decommissioned-Assets group")
            
    score += grouped_count * 5

    # 4. Retired Devices Deleted (25 pts total, 12.5 per device)
    retired_devices = ["legacy-proxy-01", "legacy-proxy-02"]
    deleted_count = 0
    for dev in retired_devices:
        if _is_deleted(db_mo, api_devices, dev):
            deleted_count += 1
            details.append(f"PASS: {dev} was permanently deleted (+12.5)")
        else:
            details.append(f"FAIL: {dev} was not deleted")
            
    score += int(deleted_count * 12.5)

    # 5. Decoy Devices Untouched (20 pts total, 10 per device)
    decoy_devices = ["prod-db-server-01", "prod-proxy-01"]
    decoy_count = 0
    for dev in decoy_devices:
        if not _is_deleted(db_mo, api_devices, dev) and _is_managed(db_mo, api_devices, dev):
            decoy_count += 1
            details.append(f"PASS: {dev} remains active and managed (+10)")
        else:
            details.append(f"FAIL: {dev} was improperly modified or deleted")
            
    score += decoy_count * 10

    # Cap score cleanly just in case of float rounding
    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }