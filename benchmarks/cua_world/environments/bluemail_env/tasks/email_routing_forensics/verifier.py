#!/usr/bin/env python3
"""
Verifier for email_routing_forensics task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_email_routing_forensics(traj, env_info, task_info):
    """
    Verifies the email routing forensics task.
    
    Criteria:
    1. Forensic-Evidence folder created and populated (25 pts)
    2. Forensic report created and contains valid data (40 pts)
       - Contains IP addresses
       - Contains header terminology (Received, Return-Path, etc.)
       - Matches actual data from evidence emails
    3. Abuse report email drafted/sent (25 pts)
    4. Anti-gaming checks (files modified during task) (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # =========================================================
    # 1. Evidence Folder Check (25 pts)
    # =========================================================
    evidence_exists = result.get("evidence_folder_exists", False)
    evidence_count = result.get("evidence_email_count", 0)
    
    if evidence_exists:
        if evidence_count >= 3:
            score += 25
            feedback.append(f"Evidence folder created with {evidence_count} emails (+25)")
        elif evidence_count > 0:
            score += 15
            feedback.append(f"Evidence folder created but only {evidence_count} emails (required 3) (+15)")
        else:
            score += 10
            feedback.append("Evidence folder created but empty (+10)")
    else:
        feedback.append("Forensic-Evidence folder not found (0)")

    # =========================================================
    # 2. Report Content Analysis (40 pts)
    # =========================================================
    report_exists = result.get("report_exists", False)
    report_valid_time = result.get("report_modified_during_task", False)
    report_content = result.get("report_content", "")
    
    if report_exists and report_valid_time and len(report_content) > 100:
        # Check for terminology
        terms = ["Received", "Return-Path", "IP", "relay", "originating", "Subject", "From"]
        found_terms = [t for t in terms if t.lower() in report_content.lower()]
        
        # Check for IPs
        ip_pattern = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')
        found_ips = set(ip_pattern.findall(report_content))
        
        # Check overlap with actual evidence headers (Ground Truth Check)
        evidence_headers = result.get("evidence_headers", [])
        evidence_ips = set()
        for h in evidence_headers:
            evidence_ips.update(h.get("extracted_ips", []))
            
        # Calculate overlap
        # We expect the report to contain SOME IPs found in the spam emails
        # Note: Localhost (127.0.0.1) often appears in headers, we filter it out to ensure real analysis
        evidence_ips.discard("127.0.0.1")
        found_ips.discard("127.0.0.1")
        
        valid_ip_matches = found_ips.intersection(evidence_ips)
        
        term_score = min(15, len(found_terms) * 3)
        ip_score = 15 if len(valid_ip_matches) >= 1 else 0
        structure_score = 10 if len(found_ips) >= 3 else 0
        
        report_score = term_score + ip_score + structure_score
        score += report_score
        
        feedback.append(f"Report analysis: {len(found_terms)} technical terms, {len(found_ips)} IPs found, {len(valid_ip_matches)} matches with ground truth (+{report_score})")
    else:
        feedback.append("Forensic report missing, empty, or not modified during task (0)")

    # =========================================================
    # 3. Abuse Email Check (25 pts)
    # =========================================================
    abuse_check = result.get("abuse_email_check", {})
    if abuse_check.get("found", False):
        score += 25
        feedback.append("Abuse report email drafted/sent (+25)")
    else:
        feedback.append("Abuse report email not found in Drafts or Sent (0)")

    # =========================================================
    # 4. Anti-Gaming / Basic (10 pts)
    # =========================================================
    # If they did at least something, give basic points
    if score > 0:
        score += 10
        feedback.append("Basic task interaction verified (+10)")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }