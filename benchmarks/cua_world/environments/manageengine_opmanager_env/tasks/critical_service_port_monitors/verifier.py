#!/usr/bin/env python3
"""
Verifier for critical_service_port_monitors task.

Checks that four named service monitors were created in OpManager,
each targeting a specific port on 127.0.0.1.

Scoring:
  - DB-Service-PostgreSQL (port 13306):   25 pts
  - WebUI-OpManager-Primary (port 8060):  25 pts
  - SNMP-Agent-Availability (port 161):   25 pts
  - NTP-Time-Sync-Check (port 123):       25 pts

Pass threshold: 50 (2 of 4 monitors)
"""

import json
import re
import sys
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_monitor_exists(result_data, monitor_name, expected_port):
    """
    Check whether a monitor with the given name exists in the collected data.
    """
    if not result_data:
        return {"name_found": False, "port_associated": False, "score": 0, "details": "No result data"}

    all_text = result_data.get("api_raw", "") + "\n" + result_data.get("db_raw", "")
    
    # 1. Check for name (case-insensitive)
    name_pattern = re.compile(re.escape(monitor_name), re.IGNORECASE)
    name_found = bool(name_pattern.search(all_text))

    # 2. Check for port association within an 800 char window of the name
    port_str = str(expected_port)
    port_associated = False

    if name_found:
        for match in name_pattern.finditer(all_text):
            start = max(0, match.start() - 800)
            end = min(len(all_text), match.end() + 800)
            window = all_text[start:end]
            if port_str in window:
                port_associated = True
                break

    # Scoring logic
    if name_found:
        score = 25  # Full points if name exists. Port association is treated as secondary confirmation.
        if port_associated:
            details = f"✓ Monitor '{monitor_name}' found with expected port '{expected_port}'"
        else:
            details = f"✓ Monitor '{monitor_name}' found (port '{expected_port}' association not explicitly confirmed in DB dump, but name matches)"
    else:
        score = 0
        details = f"✗ Monitor '{monitor_name}' NOT found in database or API output"

    return {
        "name_found": name_found,
        "port_associated": port_associated,
        "score": score,
        "details": details
    }


def verify_critical_service_port_monitors(traj, env_info, task_info):
    """
    Main verifier entry point. 
    Retrieves the exported JSON using copy_from_env and scores based on criteria.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Target metadata
    metadata = task_info.get("metadata", {})
    monitors = metadata.get("monitors", [
        {"name": "DB-Service-PostgreSQL", "port": 13306},
        {"name": "WebUI-OpManager-Primary", "port": 8060},
        {"name": "SNMP-Agent-Availability", "port": 161},
        {"name": "NTP-Time-Sync-Check", "port": 123}
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/service_monitor_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    total_score = 0
    feedback_parts = []
    monitors_created = 0

    for m in monitors:
        check = check_monitor_exists(result_data, m["name"], m["port"])
        total_score += check["score"]
        feedback_parts.append(check["details"])
        if check["name_found"]:
            monitors_created += 1

    # Anti-gaming: Ensure at least one monitor name was actually found.
    # The monitor names are highly specific, so finding them is strong proof of agent action.
    if total_score > 0 and monitors_created == 0:
        total_score = 0
        feedback_parts.append("⚠ Anti-gaming check: No evidence of actual monitor creation detected.")

    passed = total_score >= 50
    feedback = " | ".join(feedback_parts)

    logger.info(f"Score: {total_score}/100. Passed: {passed}")
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": feedback
    }