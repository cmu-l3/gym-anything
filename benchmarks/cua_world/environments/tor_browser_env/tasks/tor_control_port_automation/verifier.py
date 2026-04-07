#!/usr/bin/env python3
"""Verifier for tor_control_port_automation task.

Evaluates if the agent successfully used Python to authenticate to the Tor
Control Port, triggered a NEWNYM signal to rotate the circuit, extracted the
daemon version, and visually confirmed the IP change.
"""

import json
import logging
import os
import tempfile
import base64
import ipaddress

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def is_valid_ip(ip_str: str) -> bool:
    """Validate if a string is a valid IPv4 or IPv6 address."""
    if not ip_str:
        return False
    try:
        # Strip potential surrounding whitespace or newline chars
        clean_ip = ip_str.strip()
        ipaddress.ip_address(clean_ip)
        return True
    except ValueError:
        return False

def verify_tor_control_port(traj, env_info, task_info):
    """
    Scoring Breakdown (100 Points Total):
    1. Python script exists and contains Control Port logic (Port 9151 + NEWNYM) - 20 pts (GATE)
    2. Version file contains valid Tor version data ("0.4." or "250")            - 20 pts
    3. ip_before.txt contains a valid IP                                         - 15 pts
    4. ip_after.txt contains a valid IP                                          - 15 pts
    5. The two IPs are distinct                                                  - 15 pts
    6. Browser history confirms check.torproject.org was visited                 - 15 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/tor_control_result.json", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result: {e}")
            return {"passed": False, "score": 0, "feedback": f"Result file not found or malformed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []

    # Decode base64 payloads
    def decode_b64(payload: str) -> str:
        if not payload:
            return ""
        try:
            return base64.b64decode(payload).decode('utf-8').strip()
        except Exception:
            return ""

    script_content = decode_b64(result.get("script_b64", ""))
    version_content = decode_b64(result.get("version_b64", ""))
    ip_before = decode_b64(result.get("ip_before_b64", ""))
    ip_after = decode_b64(result.get("ip_after_b64", ""))

    # Anti-gaming check
    if not result.get("script_created_during_task", False):
        feedback_parts.append("WARNING: Python script was not created/modified during the task timeframe.")

    # Criterion 1: Script exists and contains logic [GATE]
    script_lower = script_content.lower()
    has_port = "9151" in script_lower
    has_newnym = "newnym" in script_lower
    if script_content and has_port and has_newnym:
        score += 20
        feedback_parts.append("Python script valid (contains port 9151 & NEWNYM) (20/20)")
    else:
        feedback_parts.append("Python script missing or invalid (missing '9151' or 'NEWNYM') (0/20)")
        # Gate failure
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " -> GATE FAILED: Valid script required."
        }

    # Criterion 2: Version file contains Tor version
    if version_content and ("0.4." in version_content or "250" in version_content):
        score += 20
        feedback_parts.append("Tor version extracted successfully (20/20)")
    else:
        feedback_parts.append("tor_version.txt invalid or empty (0/20)")

    # Criterion 3: ip_before is valid
    if is_valid_ip(ip_before):
        score += 15
        feedback_parts.append("Initial IP valid (15/15)")
    else:
        feedback_parts.append(f"Initial IP invalid: '{ip_before}' (0/15)")

    # Criterion 4: ip_after is valid
    if is_valid_ip(ip_after):
        score += 15
        feedback_parts.append("Post-rotation IP valid (15/15)")
    else:
        feedback_parts.append(f"Post-rotation IP invalid: '{ip_after}' (0/15)")

    # Criterion 5: IPs are distinct (Proves rotation worked)
    if is_valid_ip(ip_before) and is_valid_ip(ip_after) and ip_before != ip_after:
        score += 15
        feedback_parts.append("Circuit rotation confirmed (IPs are distinct) (15/15)")
    else:
        feedback_parts.append("Circuit rotation failed (IPs identical or missing) (0/15)")

    # Criterion 6: Browser history confirms check.torproject.org
    if result.get("history_has_check_torproject", False):
        score += 15
        feedback_parts.append("Browser history confirms check.torproject.org visit (15/15)")
    else:
        feedback_parts.append("check.torproject.org not found in browser history (0/15)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "script_found": bool(script_content),
            "ip_before": ip_before,
            "ip_after": ip_after,
            "version_extracted": version_content
        }
    }