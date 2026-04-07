#!/usr/bin/env python3
"""
Verifier for medical_device_network_security_review task.
"""

import json
import sys
import os
import tempfile
import re

def verify_medical_device_network_security_review(traj, env_info, task_info):
    """
    Verifies the security assessment task.
    
    Scoring Criteria (100 pts total):
    1. Device Creation (15 pts): Did the agent actually run a device to generate traffic?
    2. Report Existence (10 pts): File exists, valid size, written during task.
    3. Network Analysis (15 pts): Specific ports (e.g., 7400+) and protocols (UDP/TCP) mentioned.
    4. Supply Chain (20 pts): Identification of DDS middleware and other dependencies.
    5. Security Controls (20 pts): Assessment of Auth and Encryption.
    6. Findings & Recs (20 pts): Specific findings with severity and recommendations.
    
    Gate: If no device created AND (no report OR report < 100 bytes), score = 0.
    """
    
    # 1. Load result using copy_from_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    device_log = result.get('device_created_log', False)
    device_win = result.get('device_created_window', False)
    win_inc = result.get('window_increase', 0)
    
    report_info = result.get('report', {})
    report_exists = report_info.get('exists', False)
    report_content = report_info.get('content', "")
    report_size = report_info.get('size', 0)
    report_fresh = report_info.get('written_during_task', False)

    # 3. Check Gate Condition
    device_activity = device_log or device_win or (win_inc > 0)
    report_valid = report_exists and report_size > 100
    
    if not device_activity and not report_valid:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GATE FAILED: No device adapter created AND no meaningful report found. Agent did not attempt task."
        }

    score = 0
    feedback = []

    # --- Criterion 1: Device Creation (15 pts) ---
    if device_activity:
        score += 15
        feedback.append("PASS: Device adapter creation detected (Log/Window).")
    else:
        feedback.append("FAIL: No evidence of simulated device creation. Network analysis requires active traffic.")

    # --- Criterion 2: Report Basics (10 pts) ---
    if report_valid and report_fresh:
        if report_size > 800:
            score += 10
            feedback.append("PASS: Report exists and has substantial content.")
        else:
            score += 5
            feedback.append("PARTIAL: Report exists but is brief.")
    else:
        feedback.append("FAIL: Report missing, empty, or not created during task.")

    # --- Content Analysis ---
    content_lower = report_content.lower()

    # --- Criterion 3: Network Analysis (15 pts) ---
    # Look for port numbers (4-5 digits) and protocol names
    has_ports = bool(re.search(r'\b[0-9]{4,5}\b', report_content))
    has_proto = bool(re.search(r'\b(udp|tcp|multicast)\b', content_lower))
    
    if has_ports and has_proto:
        score += 15
        feedback.append("PASS: Network analysis includes specific ports and protocols.")
    elif has_ports or has_proto:
        score += 7
        feedback.append("PARTIAL: Network analysis missing either specific ports or protocols.")
    else:
        feedback.append("FAIL: No specific network details (ports/protocols) found.")

    # --- Criterion 4: Supply Chain / DDS (20 pts) ---
    # Look for DDS mentions (RTI, Connext, OpenDDS, etc) and dependencies (jar, lib, etc)
    has_dds = bool(re.search(r'\b(dds|rti|connext|opendds|rtps)\b', content_lower))
    # Look for dependency keywords from build.gradle
    deps = re.findall(r'\b(javafx|slf4j|log4j|spring|jackson|junit|gradle|hibernate|hsqldb)\b', content_lower)
    has_deps = len(set(deps)) >= 3
    
    if has_dds and has_deps:
        score += 20
        feedback.append(f"PASS: Identified DDS middleware and {len(set(deps))} dependencies.")
    elif has_dds or has_deps:
        score += 10
        feedback.append("PARTIAL: Identified either DDS or dependencies, but not both.")
    else:
        feedback.append("FAIL: Failed to identify software supply chain details (DDS/dependencies).")

    # --- Criterion 5: Security Controls (20 pts) ---
    has_auth = bool(re.search(r'\b(auth|credential|login|password|access control)\b', content_lower))
    has_enc = bool(re.search(r'\b(encrypt|tls|dtls|ssl|cleartext|plaintext|cipher)\b', content_lower))
    
    if has_auth and has_enc:
        score += 20
        feedback.append("PASS: Assessment covers both authentication and encryption.")
    elif has_auth or has_enc:
        score += 10
        feedback.append("PARTIAL: Assessment covers only one of auth or encryption.")
    else:
        feedback.append("FAIL: No assessment of security controls (auth/encryption).")

    # --- Criterion 6: Findings & Recommendations (20 pts) ---
    # Look for severity ratings
    findings = re.findall(r'\b(critical|high|medium|low)\b', content_lower)
    has_findings = len(findings) >= 3
    has_recs = bool(re.search(r'\b(recommend|remediat|should|must)\b', content_lower))
    has_decision = bool(re.search(r'\b(go|no-go|approve|deny|deploy)\b', content_lower))
    
    if has_findings and has_recs and has_decision:
        score += 20
        feedback.append("PASS: Report includes risk findings, recommendations, and decision.")
    elif has_findings or (has_recs and has_decision):
        score += 10
        feedback.append("PARTIAL: Report missing some elements of findings/recommendations.")
    else:
        feedback.append("FAIL: Findings/Recommendations section weak or missing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }