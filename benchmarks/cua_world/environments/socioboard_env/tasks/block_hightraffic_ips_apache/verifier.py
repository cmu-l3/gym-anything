#!/usr/bin/env python3
import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_hightraffic_ips(traj, env_info, task_info):
    """
    Verify that the top 3 IP addresses were accurately identified, correctly formatted,
    and successfully blocked via valid Apache configurations.
    """
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

    score = 0
    feedback_parts = []
    
    gt = result.get("ground_truth", [])
    if len(gt) < 3:
        return {"passed": False, "score": 0, "feedback": "Internal error: Ground truth not found"}
    
    expected_ips = [item["ip"] for item in gt]
    expected_counts = {item["ip"]: item["count"] for item in gt}
    
    file_exists = result.get("file_exists", False)
    content = result.get("file_content", "")
    
    # Analyze Report File
    found_ips = []
    counts_accurate = True
    format_correct = True
    
    if file_exists and content:
        lines = [line.strip() for line in content.splitlines() if line.strip()]
        for line in lines:
            # We strictly enforce the "IP : COUNT" formatting
            match = re.search(r'(\d+\.\d+\.\d+\.\d+)\s*:\s*(\d+)', line)
            if match:
                ip = match.group(1)
                count = int(match.group(2))
                found_ips.append(ip)
                if ip in expected_counts:
                    if count != expected_counts[ip]:
                        counts_accurate = False
            else:
                format_correct = False
    else:
        format_correct = False
        counts_accurate = False
        
    # Criterion 1: IPs Identified (30 pts)
    identified_count = sum(1 for ip in expected_ips if ip in found_ips)
    if identified_count == 3:
        score += 30
        feedback_parts.append("All 3 IPs identified correctly")
    else:
        score += identified_count * 10
        feedback_parts.append(f"Identified {identified_count}/3 IPs")
        
    # Criterion 2: Counts Accurate (10 pts)
    if identified_count > 0 and counts_accurate:
        score += 10
        feedback_parts.append("Log counts are mathematically accurate")
    elif identified_count > 0:
        feedback_parts.append("Log counts are inaccurate")
        
    # Criterion 3: Report Format (10 pts)
    if file_exists and format_correct and identified_count > 0:
        score += 10
        feedback_parts.append("Report format perfectly follows instructions")
    elif file_exists:
        feedback_parts.append("Report file exists but format deviates from IP : COUNT")
    else:
        feedback_parts.append("Report file missing")
        
    # Criterion 4: Apache Syntax Valid (10 pts)
    apache_configtest = result.get("apache_configtest", "")
    if "Syntax OK" in apache_configtest:
        score += 10
        feedback_parts.append("Apache syntax OK")
    else:
        feedback_parts.append("Apache syntax invalid (configuration broken)")
        
    # Criterion 5: Apache Configured (40 pts)
    config_matches = result.get("config_matches", {})
    blocked_count = sum(1 for ip in expected_ips if config_matches.get(ip, 0) > 0)
            
    if blocked_count == 3:
        score += 40
        feedback_parts.append("All 3 targeted IPs restricted in Apache config")
    else:
        score += int(blocked_count * 13.3)
        feedback_parts.append(f"{blocked_count}/3 IPs restricted in Apache config")

    # Final service health check warning
    apache_status = result.get("apache_status", "")
    if apache_status != "active":
        feedback_parts.append("Warning: Apache service failed to restart (currently inactive)")

    # Agent must correctly identify IPs AND block them in Apache to pass
    passed = (score >= 70) and (identified_count >= 2) and (blocked_count >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }