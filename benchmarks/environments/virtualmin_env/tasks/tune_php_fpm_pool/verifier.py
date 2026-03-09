#!/usr/bin/env python3
import json
import base64
import configparser
import io
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_php_fpm_pool(traj, env_info, task_info):
    """
    Verifies that the PHP-FPM pool configuration has been correctly updated.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # Load result JSON from container
    local_result_path = "task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 2. Extract Data
    config_b64 = result.get("config_content_b64", "")
    file_modified = result.get("file_modified", False)
    service_active = result.get("service_active", False)
    
    if not config_b64:
        return {"passed": False, "score": 0, "feedback": "Configuration file was empty or not found."}

    try:
        config_content = base64.b64decode(config_b64).decode('utf-8')
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": "Failed to decode configuration file."}

    # 3. Parse Configuration
    # PHP-FPM pool files are INI-style.
    # However, they sometimes use keys without sections or specific section names.
    # We'll use a loose parsing strategy or configparser with a dummy section.
    
    parser = configparser.ConfigParser()
    try:
        # Prepend a dummy section to handle file if it lacks one, 
        # though pool files usually have [domain_id] or [name]
        if not re.match(r'^\s*\[', config_content):
            parser.read_string(f"[default]\n{config_content}")
        else:
            parser.read_string(config_content)
    except configparser.Error as e:
        return {"passed": False, "score": 10, "feedback": f"Configuration file syntax error: {str(e)}"}

    # Flatten config to a simple dict (key -> value) ignoring sections for robustness
    # We assume keys are unique enough or we care about the last occurrence
    config_values = {}
    for section in parser.sections():
        for key, value in parser.items(section):
            config_values[key.lower()] = value

    # 4. Scoring Criteria
    score = 0
    feedback = []
    
    expected = task_info.get('metadata', {}).get('expected_values', {})
    
    # Helper to check integer values
    def check_int(key, expected_val, points):
        val = config_values.get(key)
        if val is None:
            feedback.append(f"Missing '{key}'")
            return 0
        try:
            if int(val) == expected_val:
                return points
            else:
                feedback.append(f"Incorrect '{key}': found {val}, expected {expected_val}")
                return 0
        except ValueError:
            feedback.append(f"Invalid format for '{key}': {val}")
            return 0

    # Helper to check string values
    def check_str(key, expected_val, points):
        val = config_values.get(key)
        if val and val.lower() == expected_val.lower():
            return points
        feedback.append(f"Incorrect/Missing '{key}': found '{val}', expected '{expected_val}'")
        return 0

    # Score breakdown
    # Total: 100
    # Values: 80 points
    # Service Active: 10 points
    # File Modified: 10 points

    score += check_str('pm', 'dynamic', 10)
    score += check_int('pm.max_children', 40, 30) # High weight as it's the main goal
    score += check_int('pm.start_servers', 10, 15)
    score += check_int('pm.min_spare_servers', 5, 10)
    score += check_int('pm.max_spare_servers', 15, 15)

    if file_modified:
        score += 10
    else:
        feedback.append("File was not modified (anti-gaming)")

    if service_active:
        score += 10
    else:
        feedback.append("PHP-FPM service is not active/running")

    # 5. Final Result
    passed = (score >= 70) and (config_values.get('pm.max_children') == '40')
    
    if passed:
        feedback.insert(0, "Configuration successfully updated.")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }