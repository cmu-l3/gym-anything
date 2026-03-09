#!/usr/bin/env python3
"""
Verifier for access_admin_system_info task.

Checks:
1. File /home/ga/system_audit_report.txt exists and was created during the task.
2. File content contains required keys.
3. Values in the file match the system ground truth (fuzzy matching).
4. VLM verification of trajectory (optional/supplementary).
"""

import json
import tempfile
import os
import logging
import base64
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content_str):
    """Parses 'key: value' lines into a dictionary."""
    data = {}
    for line in content_str.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            data[key.strip().lower()] = val.strip()
    return data

def fuzzy_match(reported, truth, field_type="text"):
    """
    Compares reported value with ground truth.
    field_type: 'text', 'version', 'number', 'bool_status'
    """
    if not reported or not truth:
        return False
        
    reported = str(reported).lower().strip()
    truth = str(truth).lower().strip()

    if field_type == "number":
        # Extract numbers and compare with tolerance
        rep_nums = re.findall(r'\d+', reported)
        truth_nums = re.findall(r'\d+', truth)
        if rep_nums and truth_nums:
            return abs(int(rep_nums[0]) - int(truth_nums[0])) <= 1
        return False

    elif field_type == "version":
        # Compare major.minor at least
        # Example: "5.7.44" vs "Ver 5.7.44 for Linux"
        # Extract X.Y.Z
        rep_ver = re.search(r'(\d+\.\d+(\.\d+)?)', reported)
        truth_ver = re.search(r'(\d+\.\d+(\.\d+)?)', truth)
        
        if rep_ver and truth_ver:
            # Check if one contains the other
            return rep_ver.group(1) in truth_ver.group(1) or truth_ver.group(1) in rep_ver.group(1)
        return False

    elif field_type == "bool_status":
        # Connected/Not Connected, True/False
        positive = ["connected", "true", "yes", "online", "active"]
        negative = ["not", "false", "no", "offline", "fail"]
        
        rep_is_pos = any(p in reported for p in positive) and not any(n in reported for n in negative)
        truth_is_pos = any(p in truth for p in positive) and not any(n in truth for n in negative)
        
        return rep_is_pos == truth_is_pos

    else: # text
        # Simple containment or reasonable overlap
        return (reported in truth) or (truth in reported)

def verify_access_admin_system_info(traj, env_info, task_info):
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
    max_score = 100
    feedback_parts = []
    
    # 1. File Existence and Freshness (20 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 20
        feedback_parts.append("Report file created successfully")
    elif result.get("file_exists"):
        score += 10
        feedback_parts.append("Report file exists but timestamp check failed (pre-existing?)")
    else:
        return {"passed": False, "score": 0, "feedback": "Report file not found"}

    # Decode content
    try:
        content_b64 = result.get("file_content_base64", "")
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
        parsed_data = parse_report_content(content)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse file content: {e}"}

    ground_truth = result.get("ground_truth", {})

    # 2. Content Verification (10 pts per field = 80 pts total)
    fields = [
        ("emoncms_version", "version"),
        ("mysql_version", "version"),
        ("php_version", "version"),
        ("redis_status", "bool_status"),
        ("server_os", "text"),
        ("feed_count", "number"),
        ("input_count", "number"),
        ("mqtt_status", "bool_status")
    ]

    correct_fields = 0
    
    for key, ftype in fields:
        reported_val = parsed_data.get(key)
        truth_val = ground_truth.get(key)
        
        if reported_val:
            if fuzzy_match(reported_val, truth_val, ftype):
                score += 10
                correct_fields += 1
            else:
                feedback_parts.append(f"Field '{key}' incorrect (Reported: '{reported_val}', Expected: ~'{truth_val}')")
        else:
            feedback_parts.append(f"Missing field: '{key}'")

    if correct_fields == len(fields):
        feedback_parts.append("All fields correct")
    else:
        feedback_parts.append(f"{correct_fields}/{len(fields)} fields correct")

    passed = score >= 60 and correct_fields >= 4

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }