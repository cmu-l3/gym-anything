#!/usr/bin/env python3
"""
Verifier for configure_active_response task.

Checks:
1. ossec.conf contains correct <command> definition
2. ossec.conf contains correct <active-response> block (rule 5763, timeout 600)
3. Wazuh manager is running
4. API confirms configuration is loaded active
5. Anti-gaming (file modified)
"""

import json
import base64
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_active_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    manager_running = result.get("manager_running", False)
    file_modified = result.get("file_modified", False)
    
    # Decode ossec.conf
    ossec_conf = ""
    if result.get("ossec_conf_base64"):
        try:
            ossec_conf = base64.b64decode(result.get("ossec_conf_base64")).decode('utf-8', errors='ignore')
        except:
            feedback.append("Failed to decode ossec.conf")

    # API Config Data
    api_config = result.get("api_config_json", {}).get("data", {}).get("affected_items", [])
    
    # --- Scoring Criteria ---

    # 1. Manager Status (15 pts)
    if manager_running:
        score += 15
        feedback.append("Wazuh manager is running")
    else:
        feedback.append("Wazuh manager is NOT running (did you restart it?)")

    # 2. File Modification Anti-Gaming (10 pts)
    if file_modified:
        score += 10
    else:
        feedback.append("ossec.conf was not modified")

    # 3. Static File Analysis (40 pts)
    # Check for Command definition
    # Regex for command: <name>firewall-drop</name> ... <executable>firewall-drop</executable>
    # Note: XML parsing with regex is fragile but sufficient for this specific structure verification
    command_block_pattern = re.compile(r"<command>.*?<name>\s*firewall-drop\s*</name>.*?<executable>\s*firewall-drop\s*</executable>.*?</command>", re.DOTALL | re.IGNORECASE)
    
    if command_block_pattern.search(ossec_conf):
        score += 20
        feedback.append("Command 'firewall-drop' defined in ossec.conf")
        
        # Check timeout allowed
        if "timeout_allowed>yes" in command_block_pattern.search(ossec_conf).group(0):
            score += 5
            feedback.append("Command timeout enabled")
    else:
        feedback.append("Command 'firewall-drop' NOT found in ossec.conf")

    # Check for Active Response definition
    # Regex: <active-response> ... <command>firewall-drop</command> ... <rules_id>...5763...</rules_id> ... <timeout>600</timeout>
    ar_block_pattern = re.compile(r"<active-response>.*?<command>\s*firewall-drop\s*</command>.*?</active-response>", re.DOTALL | re.IGNORECASE)
    ar_match = ar_block_pattern.search(ossec_conf)
    
    if ar_match:
        ar_content = ar_match.group(0)
        score += 10 # Base for having the block
        
        # Check Rule ID
        if "5763" in ar_content:
            score += 10
            feedback.append("Active response linked to rule 5763")
        else:
            feedback.append("Active response missing correct rule ID (5763)")
            
        # Check Timeout
        if "600" in ar_content:
            score += 10
            feedback.append("Active response timeout set to 600s")
        else:
            feedback.append("Active response timeout is not 600s")
    else:
        feedback.append("Active response block for 'firewall-drop' NOT found in ossec.conf")

    # 4. API / Loaded Configuration Verification (20 pts)
    # This proves the config is valid XML and actually loaded by the manager
    api_verified = False
    if api_config:
        # Flatten the list of config items (api returns list of dicts)
        # We need to find 'active-response' and 'command' sections
        ar_loaded = False
        cmd_loaded = False
        
        # Iterate over the configuration items returned by API
        # Structure varies slightly, usually [{'active-response': [...]}, {'command': [...]}] or similar
        # Depending on query, it might be a single object
        
        # Simple string check on the JSON dump is robust enough here
        import json
        api_dump = json.dumps(api_config)
        
        if "firewall-drop" in api_dump and "5763" in api_dump and "600" in api_dump:
            api_verified = True
        
    if api_verified:
        score += 20
        feedback.append("API confirms active response configuration is loaded")
    elif manager_running:
        feedback.append("Manager is running but API does not show expected configuration (did you restart?)")

    # Final logic
    passed = (score >= 65 and manager_running)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }