#!/usr/bin/env python3
"""
Verifier for create_custom_webhook_integration task.

Checks:
1. Shell wrapper script exists, is executable, and calls python script.
2. Python integration script exists, is executable, valid syntax.
3. Python script logic: reads correct args, parses JSON, uses urllib.
4. ossec.conf contains correct integration block.
5. Wazuh manager is running (configuration didn't break it).
6. Functional test passed (script doesn't crash on execution).
"""

import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_webhook_integration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    feedback = []
    
    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_hook_url = metadata.get('hook_url', "http://webhook-receiver:9999/alerts")
    target_name = metadata.get('integration_name', "custom-slack-alerts")

    # 1. Shell Script Verification (20 pts)
    if result.get('shell_exists'):
        score += 8
        feedback.append("Shell wrapper exists.")
        
        if result.get('shell_executable'):
            score += 5
            feedback.append("Shell wrapper is executable.")
            
        content = base64.b64decode(result.get('shell_content_b64', '')).decode('utf-8', errors='ignore')
        if "custom-slack-alerts.py" in content and ("$@" in content or "$*" in content):
            score += 7
            feedback.append("Shell wrapper calls Python script with arguments.")
        else:
            feedback.append("Shell wrapper does not seem to call Python script correctly.")
    else:
        feedback.append("Shell wrapper NOT found.")

    # 2. Python Script Verification (46 pts)
    if result.get('python_exists'):
        score += 8
        feedback.append("Python script exists.")
        
        if result.get('python_executable'):
            score += 5
            feedback.append("Python script is executable.")
            
        if result.get('python_valid_syntax'):
            score += 10
            feedback.append("Python script has valid syntax.")
            
            # Content Analysis
            py_content = base64.b64decode(result.get('python_content_b64', '')).decode('utf-8', errors='ignore')
            
            # Check for arg usage (sys.argv[1] and sys.argv[3])
            # Regex for sys.argv\[\s*1\s*\]
            if re.search(r'sys\.argv\[\s*1\s*\]', py_content):
                score += 8
                feedback.append("Python script reads alert file (argv[1]).")
            else:
                feedback.append("Python script does not appear to read argv[1].")
                
            if re.search(r'sys\.argv\[\s*3\s*\]', py_content):
                score += 5
                feedback.append("Python script reads hook URL (argv[3]).")
            else:
                feedback.append("Python script does not appear to read argv[3].")
            
            # Check for urllib usage (POST request)
            if "urllib.request" in py_content or "http.client" in py_content:
                score += 5
                feedback.append("Python script uses standard library for HTTP.")
            else:
                feedback.append("Python script missing urllib/http.client usage.")
                
            # Check for error handling
            if "try:" in py_content and "except" in py_content:
                score += 5
                feedback.append("Python script contains error handling.")
            else:
                feedback.append("Python script missing try/except blocks.")

        else:
            feedback.append("Python script has SYNTAX ERRORS.")
    else:
        feedback.append("Python script NOT found.")

    # 3. Configuration Verification (19 pts)
    if result.get('config_has_integration'):
        score += 8
        feedback.append("ossec.conf has integration block.")
        
        config_snippet = base64.b64decode(result.get('integration_block_b64', '')).decode('utf-8', errors='ignore')
        
        if f"<name>{target_name}</name>" in config_snippet:
            score += 3
            feedback.append("Integration name is correct.")
        
        if target_hook_url in config_snippet:
            score += 3
            feedback.append("Hook URL is correct.")
            
        if "<level>12</level>" in config_snippet:
            score += 3
            feedback.append("Alert level is correct (12).")
            
        if "<alert_format>json</alert_format>" in config_snippet:
            score += 2
            feedback.append("Alert format is correct.")
    else:
        feedback.append("Integration configuration NOT found in ossec.conf.")

    # 4. Operational Status (15 pts)
    if result.get('manager_running'):
        score += 5
        feedback.append("Wazuh manager is running.")
    else:
        feedback.append("Wazuh manager is NOT running (config error?).")
        
    if result.get('functional_test_passed'):
        score += 10
        feedback.append("Functional test passed (script runs without crashing).")
    else:
        feedback.append("Functional test FAILED.")
        output = base64.b64decode(result.get('functional_test_output_b64', '')).decode('utf-8', errors='ignore')
        if output:
            feedback.append(f"Script output: {output[:100]}...")

    # Anti-gaming check: File creation time
    task_start = result.get('task_start', 0)
    shell_mtime = result.get('shell_mtime', 0)
    if shell_mtime < task_start:
        score = 0
        feedback.append("GAMING DETECTED: Shell script predates task start.")

    passed = score >= 60 and result.get('shell_exists') and result.get('python_exists') and result.get('config_has_integration')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }