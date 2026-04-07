#!/usr/bin/env python3
"""
verifier.py — Device Snapshot Quick Links Integration

Scoring (100 pts total, pass threshold 50):
  - Splunk Link Created (25 pts): Name "Splunk-Host-Search" exists and URL contains "splunk.secops.internal"
  - IPAM Link Created (25 pts): Name "IPAM-Subnet-Lookup" exists and URL contains "netbox.infra.internal"
  - Ansible Link Created (25 pts): Name "Ansible-Playbook-Runner" exists and URL contains "awx.infra.internal"
  - Warranty Link Created (25 pts): Name "Hardware-Warranty-Check" exists and URL contains "warranty-tracker.internal"
"""

import json
import logging
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_quick_link(combined_text: str, name: str, expected_domain: str) -> bool:
    """
    Check if a quick link name and its expected target domain exist in close proximity
    within the combined data dump (case-insensitive).
    """
    lower_text = combined_text.lower()
    lower_name = name.lower()
    lower_domain = expected_domain.lower()

    idx = lower_text.find(lower_name)
    if idx == -1:
        return False

    # Check within a generous 1000-character window (both sides) around the name
    window_start = max(0, idx - 1000)
    window_end = min(len(lower_text), idx + len(lower_name) + 1000)
    window = lower_text[window_start:window_end]

    return lower_domain in window


def verify_quick_links_integration(traj, env_info, task_info):
    """Main verifier entry point."""
    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "/tmp/quick_links_result.json")
    expected_links = metadata.get("links", [])
    local_path = "/tmp/quick_links_verify_result.json"

    # Default expected links if missing from metadata
    if not expected_links:
        expected_links = [
            {"name": "Splunk-Host-Search", "domain": "splunk.secops.internal"},
            {"name": "IPAM-Subnet-Lookup", "domain": "netbox.infra.internal"},
            {"name": "Ansible-Playbook-Runner", "domain": "awx.infra.internal"},
            {"name": "Hardware-Warranty-Check", "domain": "warranty-tracker.internal"},
        ]

    # -----------------------------------------------------------------------
    # Retrieve the result file from the environment
    # -----------------------------------------------------------------------
    try:
        env_info["copy_from_env"](result_file, local_path)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                f"Could not retrieve result file '{result_file}': {e}. "
                "Ensure export_result.sh ran successfully."
            ),
        }

    # -----------------------------------------------------------------------
    # Parse the result file
    # -----------------------------------------------------------------------
    try:
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not parse result file: {e}",
        }

    # Combine DB raw text and API JSON text into one searchable corpus
    db_raw = data.get("db_raw", "")
    api_raw = json.dumps(data.get("api_raw", {}))
    combined_text = f"{db_raw} \n {api_raw}"

    score = 0
    details = []

    # Evaluate each expected link
    for link in expected_links:
        name = link["name"]
        domain = link["domain"]
        
        if _check_quick_link(combined_text, name, domain):
            score += 25
            details.append(f"PASS: Quick Link '{name}' targeting '{domain}' found (+25)")
        else:
            details.append(f"FAIL: Quick Link '{name}' targeting '{domain}' NOT found (0/25)")

    passed = score >= 50

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(details)
    }