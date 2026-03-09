#!/usr/bin/env python3
"""
Verifier for live_dns_capture_analysis task.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_live_dns_capture_analysis(traj, env_info, task_info):
    """
    Verify the live DNS capture and analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    capture = result.get('capture', {})
    report = result.get('report', {})
    task_start = result.get('task_start_time', 0)

    # === Criterion 1: Capture file exists and is valid (15 pts) ===
    if capture.get('exists') and capture.get('valid'):
        score += 15
        feedback_parts.append("Valid capture file found")
    elif capture.get('exists'):
        score += 5
        feedback_parts.append("Capture file exists but is invalid")
    else:
        feedback_parts.append("Capture file missing")
        # Critical failure if no capture
        return {"passed": False, "score": 0, "feedback": "No capture file found"}

    # === Criterion 2: Capture contains DNS packets (10 pts) ===
    dns_count = capture.get('dns_packet_count', 0)
    if dns_count > 0:
        score += 10
        feedback_parts.append(f"Capture contains {dns_count} DNS packets")
    else:
        feedback_parts.append("No DNS packets in capture")

    # === Criterion 3, 4, 5: Specific Domains (10 pts each) ===
    found_domains = capture.get('found_domains', [])
    for domain in ["example.com", "example.org", "example.net"]:
        if domain in found_domains:
            score += 10
            feedback_parts.append(f"Found traffic for {domain}")
        else:
            feedback_parts.append(f"Missing traffic for {domain}")

    # === Criterion 6: Anti-Gaming Timestamp Check (10 pts) ===
    # Capture file modified time must be > task start time
    if capture.get('mtime', 0) > task_start:
        score += 10
        feedback_parts.append("Capture is new (created during task)")
    else:
        feedback_parts.append("Capture file timestamp predates task (possible gaming)")

    # === Criterion 7: Report file exists (10 pts) ===
    if report.get('exists'):
        score += 10
        feedback_parts.append("Report file found")
    else:
        feedback_parts.append("Report file missing")

    # === Criterion 8: Report packet count accuracy (10 pts) ===
    report_content = report.get('content', "")
    if report.get('exists') and dns_count > 0:
        # Look for "Total DNS packets: 12" pattern
        match = re.search(r'Total DNS packets:\s*(\d+)', report_content, re.IGNORECASE)
        if match:
            reported_count = int(match.group(1))
            # Tolerance +/- 50%
            if 0.5 * dns_count <= reported_count <= 1.5 * dns_count:
                score += 10
                feedback_parts.append(f"Reported count ({reported_count}) matches actual ({dns_count})")
            else:
                feedback_parts.append(f"Reported count ({reported_count}) mismatches actual ({dns_count})")
        else:
            feedback_parts.append("Could not parse total packet count from report")

    # === Criterion 9: Report mentions all 3 domains (5 pts) ===
    domains_in_report = 0
    for domain in ["example.com", "example.org", "example.net"]:
        if domain in report_content:
            domains_in_report += 1
    
    if domains_in_report == 3:
        score += 5
        feedback_parts.append("Report mentions all 3 domains")
    else:
        feedback_parts.append(f"Report mentions {domains_in_report}/3 domains")

    # === Criterion 10: Report IPs match capture (10 pts) ===
    # Check if IPs extracted from pcap appear in report
    captured_ips_raw = capture.get('captured_ips_raw', "")
    ip_matches = 0
    
    # Parse our raw IP string "example.com:1.2.3.4|example.org:5.6.7.8"
    if captured_ips_raw:
        entries = captured_ips_raw.split('|')
        for entry in entries:
            if ':' in entry:
                domain, ip_str = entry.split(':', 1)
                ips = ip_str.split()
                # Check if ANY of the real IPs for this domain appear in the report
                for ip in ips:
                    # Simple check: does the IP appear in the report?
                    # Better check: does it appear on the line for that domain?
                    # We'll do a simple global check for robustness
                    if ip in report_content:
                        ip_matches += 1
                        break # Count domain as matched once
    
    if ip_matches >= 2:
        score += 10
        feedback_parts.append("Reported IPs match captured data")
    elif ip_matches > 0:
        score += 5
        feedback_parts.append("Some reported IPs match captured data")
    
    # Determine Pass/Fail
    # Must have score >= 70 AND captured data for at least 2 domains
    data_ok = len(found_domains) >= 2
    passed = (score >= 70) and data_ok

    if not data_ok:
        feedback_parts.append("FAIL: Did not capture traffic for enough target domains")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }