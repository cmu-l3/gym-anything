#!/usr/bin/env python3
"""
Verifier for Emoncms System Health Report task.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_report_content(content):
    """
    Parses the KEY: VALUE format from the report string.
    Returns a dictionary of normalized keys to values.
    """
    data = {}
    if not content:
        return data
        
    for line in content.splitlines():
        if ':' in line:
            key, val = line.split(':', 1)
            # Normalize key: uppercase, strip whitespace
            clean_key = key.strip().upper()
            data[clean_key] = val.strip()
    return data

def verify_system_health_report(traj, env_info, task_info):
    """
    Verifies the system health report task.
    
    Scoring Rubric (Total 100):
    - File exists & created during task: 10 pts
    - Feed Count (±1): 15 pts
    - Input Count (±2): 15 pts
    - MySQL Version (match major.minor): 12 pts
    - PHP Version (match major.minor): 12 pts
    - Redis Status (semantic match): 12 pts
    - Emoncms Version (substring match): 12 pts
    - MQTT Status (semantic match): 12 pts
    
    Pass Threshold: 70
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found."}
    
    if not result.get("file_created_during_task", False):
        feedback_parts.append("File exists but was not created/modified during task.")
        # We penalize but allow continuing to check content
    else:
        score += 10
        feedback_parts.append("File created successfully.")

    if result.get("file_size", 0) < 10:
        feedback_parts.append("File is empty or too small.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Parse Agent Content and Ground Truth
    raw_content = result.get("report_content_raw", "")
    agent_data = parse_report_content(raw_content)
    ground_truth = result.get("ground_truth", {})

    logger.info(f"Agent Data: {agent_data}")
    logger.info(f"Ground Truth: {ground_truth}")

    # Helper for checking numeric counts with tolerance
    def check_count(key, gt_val, tolerance, points):
        agent_val_str = agent_data.get(key)
        if not agent_val_str:
            return 0, f"{key} missing"
        
        # Extract number from string (handle cases like '5 feeds')
        nums = re.findall(r'\d+', agent_val_str)
        if not nums:
            return 0, f"{key} invalid format ({agent_val_str})"
        
        agent_val = int(nums[0])
        diff = abs(agent_val - gt_val)
        
        if diff <= tolerance:
            return points, f"{key} correct ({agent_val})"
        else:
            return 0, f"{key} incorrect (got {agent_val}, expected {gt_val})"

    # Helper for checking string matches
    def check_string(key, gt_val, points, strict=False):
        agent_val = agent_data.get(key, "").lower()
        gt_val = str(gt_val).lower()
        
        if not agent_val:
            return 0, f"{key} missing"
            
        if strict:
            if gt_val == agent_val:
                return points, f"{key} correct"
        else:
            # Flexible matching (substring or common terms)
            if gt_val in agent_val or agent_val in gt_val:
                 return points, f"{key} correct"
            # Special case for versions: match "X.Y"
            if re.search(r'\d+\.\d+', gt_val) and re.search(r'\d+\.\d+', agent_val):
                 gt_nums = re.findall(r'\d+\.\d+', gt_val)[0]
                 agent_nums = re.findall(r'\d+\.\d+', agent_val)[0]
                 if gt_nums == agent_nums:
                     return points, f"{key} correct"

        return 0, f"{key} incorrect (got '{agent_val}', expected '{gt_val}')"

    # 2. Check Feed Count (15 pts)
    pts, fb = check_count("FEED_COUNT", ground_truth.get("feed_count", 0), 1, 15)
    score += pts
    feedback_parts.append(fb)

    # 3. Check Input Count (15 pts)
    pts, fb = check_count("INPUT_COUNT", ground_truth.get("input_count", 0), 2, 15)
    score += pts
    feedback_parts.append(fb)

    # 4. MySQL Version (12 pts)
    pts, fb = check_string("MYSQL_VERSION", ground_truth.get("mysql_version", "unknown"), 12)
    score += pts
    feedback_parts.append(fb)

    # 5. PHP Version (12 pts)
    pts, fb = check_string("PHP_VERSION", ground_truth.get("php_version", "unknown"), 12)
    score += pts
    feedback_parts.append(fb)

    # 6. Redis Status (12 pts)
    # Handle "connected" vs "running" vs "enabled"
    redis_gt = ground_truth.get("redis_status", "Disconnected").lower()
    redis_agent = agent_data.get("REDIS_STATUS", "").lower()
    
    redis_positive = ["connected", "enabled", "running", "yes", "true", "active"]
    redis_negative = ["disconnected", "disabled", "stopped", "no", "false", "inactive", "error"]
    
    is_gt_positive = any(x in redis_gt for x in redis_positive)
    is_agent_positive = any(x in redis_agent for x in redis_positive)
    
    if not redis_agent:
        feedback_parts.append("REDIS_STATUS missing")
    elif is_gt_positive == is_agent_positive:
        score += 12
        feedback_parts.append(f"REDIS_STATUS correct ({redis_agent})")
    else:
        feedback_parts.append(f"REDIS_STATUS incorrect (got '{redis_agent}', expected '{redis_gt}')")

    # 7. Emoncms Version (12 pts)
    pts, fb = check_string("EMONCMS_VERSION", ground_truth.get("emoncms_version", "unknown"), 12)
    score += pts
    feedback_parts.append(fb)

    # 8. MQTT Status (12 pts)
    mqtt_gt = ground_truth.get("mqtt_status", "Disabled").lower()
    mqtt_agent = agent_data.get("MQTT_STATUS", "").lower()
    
    is_gt_positive = any(x in mqtt_gt for x in ["connected", "enabled", "running"])
    is_agent_positive = any(x in mqtt_agent for x in ["connected", "enabled", "running"])
    
    if not mqtt_agent:
        feedback_parts.append("MQTT_STATUS missing")
    elif is_gt_positive == is_agent_positive:
        score += 12
        feedback_parts.append(f"MQTT_STATUS correct ({mqtt_agent})")
    else:
        feedback_parts.append(f"MQTT_STATUS incorrect (got '{mqtt_agent}', expected '{mqtt_gt}')")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }