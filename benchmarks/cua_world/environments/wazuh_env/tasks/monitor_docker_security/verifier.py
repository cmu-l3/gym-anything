#!/usr/bin/env python3
import json
import base64
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_monitor_docker_security(traj, env_info, task_info):
    """
    Verify the Wazuh Docker security monitoring task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
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
    
    # Decode contents
    try:
        ossec_conf = base64.b64decode(result.get("ossec_conf_b64", "")).decode('utf-8', errors='ignore')
        rules_xml = base64.b64decode(result.get("rules_xml_b64", "")).decode('utf-8', errors='ignore')
        last_alert_raw = result.get("last_alert_b64", "")
        last_alert = json.loads(base64.b64decode(last_alert_raw).decode('utf-8')) if last_alert_raw else None
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to decode result data: {e}"}

    # 1. Verify Docker Listener Enabled in ossec.conf (30 pts)
    # Looking for <wodle name="docker-listener"> ... <disabled>no</disabled> (default is no if missing) 
    # OR just existence without disabled=yes
    
    # Simple regex check
    listener_block = re.search(r'<wodle name="docker-listener">.*?</wodle>', ossec_conf, re.DOTALL)
    listener_enabled = False
    
    if listener_block:
        block_content = listener_block.group(0)
        if "<disabled>yes</disabled>" not in block_content:
            listener_enabled = True
            
    if listener_enabled:
        score += 30
        feedback_parts.append("Docker listener enabled")
    else:
        feedback_parts.append("Docker listener NOT enabled in ossec.conf")

    # 2. Verify Rule 100205 Created (30 pts)
    rule_exists = False
    rule_correct = False
    
    # Check for rule ID 100205
    if 'id="100205"' in rules_xml or "id='100205'" in rules_xml:
        rule_exists = True
        score += 20  # Base points for existence
        
        # Check specific logic: docker.image contains crypto-miner
        # Regex to find the rule block
        rule_match = re.search(r'<rule[^>]*id="100205"[^>]*>(.*?)</rule>', rules_xml, re.DOTALL)
        if rule_match:
            rule_content = rule_match.group(1)
            # Check for image match
            if "crypto-miner" in rule_content and ("docker.image" in rule_content or "field name=\"docker.image\"" in rule_content):
                rule_correct = True
                score += 20 # Bonus for correctness (total 40 for this section)
                feedback_parts.append("Custom rule 100205 created correctly")
            else:
                feedback_parts.append("Rule 100205 exists but logic seems incorrect (missing crypto-miner or field)")
        else:
             feedback_parts.append("Rule 100205 ID found but could not parse block")
    else:
        feedback_parts.append("Rule 100205 NOT found in local_rules.xml")

    # 3. Verify Alert Triggered (30 pts)
    alert_triggered = False
    hit_count = result.get("alert_hit_count", 0)
    
    if hit_count > 0:
        alert_triggered = True
        score += 30
        feedback_parts.append("Alert triggered successfully")
    else:
        feedback_parts.append("No alert triggered for rule 100205")

    # 4. Verify Image Tagging (Anti-gaming / completeness)
    image_tagged = result.get("image_tagged", 0)
    if image_tagged > 0:
        feedback_parts.append("Docker image tagged correctly")
    else:
        feedback_parts.append("Warning: 'crypto-miner' image tag not found (did you run the simulation?)")

    # Final Check
    passed = (listener_enabled and rule_exists and alert_triggered)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }