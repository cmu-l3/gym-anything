#!/usr/bin/env python3
"""
Verifier for configure_asset_inventory_scan task.

Criteria:
1. Wazuh Manager configuration (ossec.conf) has syscollector interval set to 3m (30 points).
2. `socat` package is installed on the manager (20 points).
3. Wazuh Manager was restarted (uptime < task duration) (10 points).
4. Output JSON file exists and contains valid data for `socat` from the API (30 points).
5. Output file was created during the task (10 points).
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_asset_inventory_scan(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Configuration Check (30 pts) ---
    config_content = result.get('ossec_config', '')
    
    # Regex to find the syscollector wodle and its interval
    # Looks for <wodle name="syscollector"> ... <interval>3m</interval> ... </wodle>
    # Note: re.DOTALL makes . match newlines
    syscollector_match = re.search(r'<wodle name="syscollector">.*?</wodle>', config_content, re.DOTALL)
    
    config_passed = False
    if syscollector_match:
        block = syscollector_match.group(0)
        # Check for 3m or 180s
        if re.search(r'<interval>\s*(3m|180s)\s*</interval>', block):
            score += 30
            config_passed = True
            feedback_parts.append("Configuration: Syscollector interval set to 3m.")
        else:
            feedback_parts.append("Configuration: Syscollector interval NOT set to 3m.")
    else:
        feedback_parts.append("Configuration: Syscollector block not found in ossec.conf.")

    # --- Criterion 2: Package Installation (20 pts) ---
    if result.get('socat_installed', False):
        score += 20
        feedback_parts.append("System: 'socat' is installed.")
    else:
        feedback_parts.append("System: 'socat' is NOT installed.")

    # --- Criterion 3: Service Restart (10 pts) ---
    uptime = result.get('manager_uptime_seconds', 99999)
    # If uptime is less than task duration (plus a buffer), it was restarted
    # We use a generous buffer because uptime resets on restart
    # Actually, we just need to know if it's "fresh" relative to task start. 
    # The export script calculates task duration.
    # If uptime < task_duration, implies start happened after task start.
    task_duration = result.get('task_duration_seconds', 600)
    
    if uptime < task_duration:
        score += 10
        feedback_parts.append("Service: Manager was restarted.")
    else:
        feedback_parts.append(f"Service: Manager uptime ({uptime}s) > task duration. Did you restart?")

    # --- Criterion 4 & 5: Output File (40 pts total) ---
    output_exists = result.get('output_file_exists', False)
    output_fresh = result.get('output_file_created_during_task', False)
    output_content_raw = result.get('output_content', '')
    
    output_valid = False
    if output_exists:
        if output_fresh:
            score += 10
            feedback_parts.append("Output: File created during task.")
        else:
            feedback_parts.append("Output: File existed before task (stale).")
        
        # Parse JSON content
        try:
            # The API returns a structure like {"data": {"affected_items": [{"name": "socat", ...}]}}
            # Or the user might have saved just the list item. We should be flexible.
            data = json.loads(output_content_raw)
            
            # Helper to find socat in various structures
            found_socat = False
            
            # Case A: Full API response
            if isinstance(data, dict) and 'data' in data:
                items = data['data'].get('affected_items', [])
                for item in items:
                    if item.get('name') == 'socat':
                        found_socat = True
                        break
            
            # Case B: Just the item dict or list of items
            elif isinstance(data, list):
                for item in data:
                    if isinstance(item, dict) and item.get('name') == 'socat':
                        found_socat = True
                        break
            elif isinstance(data, dict) and data.get('name') == 'socat':
                found_socat = True

            if found_socat:
                score += 30
                output_valid = True
                feedback_parts.append("Output: Valid JSON containing 'socat' details found.")
            else:
                feedback_parts.append("Output: JSON valid but 'socat' package details not found.")
                
        except json.JSONDecodeError:
            feedback_parts.append("Output: File contains invalid JSON.")
    else:
        feedback_parts.append("Output: Result file not found.")

    # --- Final Result ---
    # Pass if Config is correct AND Output is valid
    passed = config_passed and output_valid and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }