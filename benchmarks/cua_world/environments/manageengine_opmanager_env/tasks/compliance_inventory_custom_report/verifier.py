#!/usr/bin/env python3
"""
verifier.py — Compliance Inventory Custom Report

Scoring (100 pts total, pass at 65):
  - Report Exists: 40 pts (Must find 'SOC2-Infrastructure-Inventory')
  - Device Module Selected: 10 pts
  - Basic Columns Included: 25 pts (Device Name, IP Address)
  - Advanced Columns Included: 25 pts (Vendor, Category, Uptime)
"""

import json
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TARGET_REPORT_NAME = "soc2-infrastructure-inventory"

# Column variations that might appear in the DB/API
BASIC_COLS = {
    "device_name": ["device name", "displayname", "display name", "name", "sysname", "devicename"],
    "ip_address":  ["ip address", "ipaddress", "ip_address", "ip"]
}

ADVANCED_COLS = {
    "vendor":      ["vendor"],
    "category":    ["category", "type", "devicetype"],
    "uptime":      ["uptime", "system uptime", "sysuptime"]
}

def _search_all(data: dict) -> str:
    """Return a lower-cased string representation of all collected data."""
    return json.dumps(data).lower()

def _check_presence(text: str, keywords: list) -> bool:
    """Check if any of the keyword synonyms are present in the text."""
    for kw in keywords:
        if kw in text:
            return True
    return False

def verify_compliance_inventory_custom_report(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/compliance_report_result.json")
    local_path = "/tmp/compliance_report_verify_result.json"

    # -----------------------------------------------------------------------
    # Retrieve the result file
    # -----------------------------------------------------------------------
    if "copy_from_env" not in env_info:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}. Check that export_result.sh ran successfully."
        }

    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse result file: {e}"}

    combined_text = _search_all(data)
    
    score = 0
    details = []

    # -----------------------------------------------------------------------
    # Criterion 1: Report Exists (40 pts)
    # -----------------------------------------------------------------------
    report_exists = TARGET_REPORT_NAME in combined_text
    
    if report_exists:
        score += 40
        details.append(f"PASS: Custom report '{TARGET_REPORT_NAME}' found (+40)")
    else:
        details.append(f"FAIL: Custom report '{TARGET_REPORT_NAME}' not found in API or DB (0/40)")
        # Early exit if the core requirement isn't met, to prevent false positives from default tables
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(details)
        }

    # -----------------------------------------------------------------------
    # Since we use relational DB dumps, the Report and its columns might be in
    # different tables (e.g., ReportTemplate vs ReportColumn). 
    # We will search the entire dump text for the column names. Since the report
    # exists, finding these columns in the recent DB rows strongly indicates success.
    # -----------------------------------------------------------------------
    
    # Criterion 2: Device Module Selected (10 pts)
    # Checking for typical module identifiers: 'device', 'inventory', 'node'
    module_synonyms = ["device", "inventory", "node"]
    if _check_presence(combined_text, module_synonyms):
        score += 10
        details.append("PASS: Device/Inventory module identifier found (+10)")
    else:
        details.append("FAIL: Device/Inventory module identifier not found (0/10)")

    # Criterion 3: Basic Columns (25 pts)
    found_basic = True
    for col_key, synonyms in BASIC_COLS.items():
        if not _check_presence(combined_text, synonyms):
            found_basic = False
            details.append(f"FAIL: Basic column '{col_key}' not found")
    
    if found_basic:
        score += 25
        details.append("PASS: All required basic columns (Device Name, IP Address) found (+25)")

    # Criterion 4: Advanced Columns (25 pts)
    found_adv = True
    for col_key, synonyms in ADVANCED_COLS.items():
        if not _check_presence(combined_text, synonyms):
            found_adv = False
            details.append(f"FAIL: Advanced column '{col_key}' not found")
            
    if found_adv:
        score += 25
        details.append("PASS: All required advanced columns (Vendor, Category, Uptime) found (+25)")

    # Final logic
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }