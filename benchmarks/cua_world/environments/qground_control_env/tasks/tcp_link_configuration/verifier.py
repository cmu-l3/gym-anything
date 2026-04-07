#!/usr/bin/env python3
"""
Verifier for tcp_link_configuration@1

Checks:
1. QGC AutoconnectUDP disabled (20 pts)
2. TCP link config with port 5762 in QGC settings (20 pts)
3. TCP:5762 MAVLink active (15 pts)
4. Report file exists (10 pts)
5. Report modified during task (5 pts)
6. Report contains link name "LTE_Field_Relay" (10 pts)
7. Report contains vehicle/firmware info (10 pts)
8. Report contains TCP + port details (10 pts)

Total: 100 pts
Pass threshold: 70 pts
"""

import json
import re
import sys
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tcp_link_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/task_result.json')

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    max_score = 100
    details = []
    
    task_start = result_data.get("task_start_time", 0)
    qgc_ini = result_data.get("qgc_ini", {})
    tcp_conn = result_data.get("tcp_connectivity", {})
    report = result_data.get("report", {})
    baseline = result_data.get("baseline_ini", {})
    
    # ── 1. AutoconnectUDP disabled (20 pts) ──────────────────────────────
    ini_content = str(qgc_ini.get("content", "")).lower()
    baseline_content = str(baseline.get("content", "")).lower()
    
    udp_disabled = False
    for pattern in [r'autoconnectudp\s*=\s*(false|0)', r'autoconnect.*udp\s*=\s*(false|0)']:
        if re.search(pattern, ini_content):
            udp_disabled = True
            break
            
    # Also verify it actually changed from baseline
    baseline_had_true = "autoconnectudp=true" in baseline_content.replace(" ", "")
    
    if udp_disabled:
        if baseline_had_true:
            score += 20
            details.append("PASS (20 pts): AutoconnectUDP disabled (changed from true to false)")
        else:
            # Config was false but we can't confirm change from baseline
            score += 10
            details.append("PARTIAL (10 pts): AutoconnectUDP is false but cannot confirm change from baseline")
    else:
        details.append("FAIL (0 pts): AutoconnectUDP not disabled")
    
    # ── 2. TCP link config present (20 pts) ──────────────────────────────
    has_tcp_in_ini = bool(re.search(r'(type|protocol)\s*=\s*\d*\s*.*tcp|tcp.*link|linktype.*=.*[23]', ini_content))
    has_5762_in_ini = "5762" in ini_content
    has_name_in_ini = bool(re.search(r'lte.?field.?relay', ini_content, re.IGNORECASE))
    
    tcp_config_score = 0
    if has_tcp_in_ini and has_5762_in_ini:
        tcp_config_score += 15
        details.append("PASS (15 pts): TCP link with port 5762 found in QGC config")
    elif has_5762_in_ini:
        tcp_config_score += 8
        details.append("PARTIAL (8 pts): Port 5762 found in config but TCP type unclear")
    elif has_tcp_in_ini:
        tcp_config_score += 5
        details.append("PARTIAL (5 pts): TCP link found but port 5762 not confirmed")
    else:
        details.append("FAIL (0 pts): No TCP link configuration found in QGC settings")
    
    # Bonus for link name
    if has_name_in_ini:
        tcp_config_score += 5
        details.append("BONUS (5 pts): Link name 'LTE_Field_Relay' found in config")
    
    tcp_config_score = min(tcp_config_score, 20)
    score += tcp_config_score
    
    # ── 3. TCP:5762 MAVLink active (15 pts) ──────────────────────────────
    tcp_active = tcp_conn.get("active", False)
    heartbeat_count = tcp_conn.get("heartbeat_count", 0)
    
    if tcp_active and heartbeat_count >= 1:
        score += 15
        details.append(f"PASS (15 pts): TCP:5762 MAVLink active ({heartbeat_count} heartbeats)")
    elif tcp_active:
        score += 10
        details.append("PARTIAL (10 pts): TCP:5762 connected but limited heartbeats")
    else:
        details.append("FAIL (0 pts): TCP:5762 MAVLink not active")
    
    # ── 4. Report file exists (10 pts) ───────────────────────────────────
    report_exists = report.get("exists", False)
    report_size = report.get("size", 0)
    
    if report_exists and report_size > 50:
        score += 10
        details.append(f"PASS (10 pts): Report file exists ({report_size} bytes)")
    elif report_exists:
        score += 5
        details.append(f"PARTIAL (5 pts): Report file exists but very small ({report_size} bytes)")
    else:
        details.append("FAIL (0 pts): Report file not found")
    
    # ── 5. Report modified during task (5 pts) ──────────────────────────
    report_mtime = report.get("mtime", 0)
    
    if report_exists and report_mtime >= int(task_start):
        score += 5
        details.append("PASS (5 pts): Report was created/modified during task window")
    elif report_exists:
        details.append("FAIL (0 pts): Report exists but was not modified during task window")
    else:
        details.append("SKIP (0 pts): No report file to check timestamp")
    
    # ── 6. Report contains link name (10 pts) ───────────────────────────
    report_content = str(report.get("content", "")).lower()
    
    if re.search(r'lte.?field.?relay', report_content):
        score += 10
        details.append("PASS (10 pts): Report contains 'LTE_Field_Relay' link name")
    elif "lte" in report_content and "relay" in report_content:
        score += 5
        details.append("PARTIAL (5 pts): Report mentions LTE and relay but not exact name")
    else:
        details.append("FAIL (0 pts): Report does not contain link name 'LTE_Field_Relay'")
    
    # ── 7. Report contains vehicle info (10 pts) ────────────────────────
    vehicle_patterns = [
        r'arducopter', r'ardu\s*copter', r'copter',
        r'vehicle\s*type', r'firmware', r'ardupilot',
        r'quadcopter', r'multirotor'
    ]
    vehicle_found = any(re.search(p, report_content) for p in vehicle_patterns)
    
    if vehicle_found:
        score += 10
        details.append("PASS (10 pts): Report contains vehicle/firmware information")
    else:
        details.append("FAIL (0 pts): Report missing vehicle/firmware information")
    
    # ── 8. Report contains TCP + port details (10 pts) ──────────────────
    has_tcp_in_report = "tcp" in report_content
    has_port_in_report = "5762" in report_content
    
    if has_tcp_in_report and has_port_in_report:
        score += 10
        details.append("PASS (10 pts): Report contains TCP protocol and port 5762")
    elif has_tcp_in_report or has_port_in_report:
        score += 5
        details.append("PARTIAL (5 pts): Report mentions TCP or port but not both")
    else:
        details.append("FAIL (0 pts): Report missing TCP connection details")
    
    # ── Final scoring ────────────────────────────────────────────────────
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(details),
        "details": {"score": score, "max_score": max_score, "logs": details}
    }