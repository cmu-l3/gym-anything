#!/usr/bin/env python3
"""
verifier.py — Endpoint Security Baseline Template Setup

Scoring (100 pts total, pass threshold 60):
  Criterion 1: Service csagent (CrowdStrike-Falcon-Sensor) exists         — 20 pts
  Criterion 2: Service QualysAgent (Qualys-Cloud-Agent) exists            — 20 pts
  Criterion 3: Service SplunkForwarder (Splunk-Universal-Forwarder) exists— 20 pts
  Criterion 4: Template Windows-Server-Secure-Baseline with OID exists    — 40 pts
"""

import json
import os
import sys

RESULT_FILE = "/tmp/endpoint_security_result.json"

def _load_result():
    if not os.path.exists(RESULT_FILE):
        return {}
    try:
        with open(RESULT_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def _check_entity(api_data, db_raw, identifiers):
    """
    Check if ALL string identifiers for a given entity exist together.
    Searches both the API JSON payload and the raw DB dump.
    """
    # Check DB text
    db_lower = db_raw.lower() if db_raw else ""
    if all(ident.lower() in db_lower for ident in identifiers):
        return True, "Found in database raw dump."

    # Check API text
    api_text = json.dumps(api_data).lower() if api_data else ""
    if all(ident.lower() in api_text for ident in identifiers):
        return True, "Found in API response data."

    return False, "Not found."

def verify_endpoint_security_baseline_template_setup(traj=None, env_info=None, task_info=None):
    if env_info and 'copy_from_env' in env_info:
        result_file = (task_info or {}).get('metadata', {}).get('result_file', RESULT_FILE)
        local_path = '/tmp/endpoint_security_verify_result.json'
        try:
            env_info['copy_from_env'](result_file, local_path)
            with open(local_path) as f:
                result_data = json.load(f)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not retrieve or parse result file: {e}",
            }
    else:
        result_data = _load_result()

    if not result_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file is missing or empty. Check that export_result.sh ran successfully.",
        }

    services_api = result_data.get("windows_services_api", {})
    templates_api = result_data.get("device_templates_api", {})
    db_raw = result_data.get("db_raw_dump", "")
    
    score = 0
    feedback_details = []

    # 1. Check CrowdStrike Service
    cs_found, msg1 = _check_entity(services_api, db_raw, ["csagent", "CrowdStrike-Falcon-Sensor"])
    if cs_found:
        score += 20
        feedback_details.append("PASS: CrowdStrike service configured (+20)")
    else:
        feedback_details.append("FAIL: CrowdStrike service 'csagent' / 'CrowdStrike-Falcon-Sensor' not found (0/20)")

    # 2. Check Qualys Service
    qy_found, msg2 = _check_entity(services_api, db_raw, ["QualysAgent", "Qualys-Cloud-Agent"])
    if qy_found:
        score += 20
        feedback_details.append("PASS: Qualys service configured (+20)")
    else:
        feedback_details.append("FAIL: Qualys service 'QualysAgent' / 'Qualys-Cloud-Agent' not found (0/20)")

    # 3. Check Splunk Service
    sp_found, msg3 = _check_entity(services_api, db_raw, ["SplunkForwarder", "Splunk-Universal-Forwarder"])
    if sp_found:
        score += 20
        feedback_details.append("PASS: Splunk service configured (+20)")
    else:
        feedback_details.append("FAIL: Splunk service 'SplunkForwarder' / 'Splunk-Universal-Forwarder' not found (0/20)")

    # 4. Check Device Template
    dt_found, msg4 = _check_entity(templates_api, db_raw, ["Windows-Server-Secure-Baseline", ".1.3.6.1.4.1.311.1.1.3.1.3"])
    if dt_found:
        score += 40
        feedback_details.append("PASS: Device template 'Windows-Server-Secure-Baseline' with correct OID found (+40)")
    else:
        feedback_details.append("FAIL: Device template 'Windows-Server-Secure-Baseline' or OID '.1.3.6.1.4.1.311.1.1.3.1.3' not found (0/40)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_details)
    }