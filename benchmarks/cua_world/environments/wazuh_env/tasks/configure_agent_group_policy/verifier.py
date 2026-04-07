#!/usr/bin/env python3
"""
Verifier for configure_agent_group_policy task.

Verifies:
1. Agent group 'linux-webservers' exists.
2. Shared agent.conf exists and was created during the task.
3. agent.conf contains correct XML structure and values.
"""

import json
import os
import tempfile
import base64
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_agent_group_policy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check Group Existence (15 pts)
    if result.get("group_exists"):
        score += 15
        feedback.append("Group 'linux-webservers' created successfully.")
    else:
        feedback.append("Group 'linux-webservers' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Check Config Existence & Timing (10 pts)
    if not result.get("config_exists"):
        feedback.append("agent.conf not found in group directory.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    
    if result.get("config_created_during_task"):
        score += 5
        feedback.append("Configuration created during task.")
    else:
        feedback.append("Configuration file timestamp indicates it wasn't updated during this task.")

    # 3. Parse and Verify Config Content
    config_b64 = result.get("config_content_b64", "")
    if not config_b64:
        feedback.append("Configuration file is empty.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    try:
        config_xml = base64.b64decode(config_b64).decode('utf-8')
        # Wrap in a dummy root if agent didn't provide one, though standard is <agent_config>
        # The agent.conf usually starts with <agent_config>
        if not config_xml.strip().startswith("<"):
             raise ValueError("Not XML")
        
        # Parse XML
        root = ET.fromstring(config_xml)
        
        score += 5  # Valid XML
        feedback.append("Configuration is valid XML.")

        # -- Verify Localfiles (30 pts total) --
        localfiles = root.findall("localfile")
        apache_access = False
        apache_error = False
        syslog_auth = False

        for lf in localfiles:
            fmt = lf.find("log_format")
            loc = lf.find("location")
            if fmt is not None and loc is not None:
                if fmt.text == "apache" and loc.text == "/var/log/apache2/access.log":
                    apache_access = True
                elif fmt.text == "apache" and loc.text == "/var/log/apache2/error.log":
                    apache_error = True
                elif fmt.text == "syslog" and loc.text == "/var/log/auth.log":
                    syslog_auth = True
        
        if apache_access: score += 10
        else: feedback.append("Missing or incorrect Apache access log config.")
        
        if apache_error: score += 10
        else: feedback.append("Missing or incorrect Apache error log config.")
        
        if syslog_auth: score += 10
        else: feedback.append("Missing or incorrect Syslog auth log config.")

        # -- Verify Syscheck (25 pts total) --
        syscheck = root.find("syscheck")
        if syscheck is not None:
            freq = syscheck.find("frequency")
            if freq is not None and freq.text == "600":
                score += 5
            else:
                feedback.append("Syscheck frequency incorrect (expected 600).")

            html_dir_ok = False
            etc_dir_ok = False
            
            for d in syscheck.findall("directories"):
                if d.text == "/var/www/html" and d.get("realtime") == "yes":
                    html_dir_ok = True
                if d.text == "/etc/apache2" and d.get("check_all") == "yes" and d.get("report_changes") == "yes":
                    etc_dir_ok = True
            
            if html_dir_ok: score += 15
            else: feedback.append("Syscheck /var/www/html config incorrect.")
            
            if etc_dir_ok: score += 5
            else: feedback.append("Syscheck /etc/apache2 config incorrect.")
        else:
            feedback.append("Syscheck section missing.")

        # -- Verify Wodle (15 pts total) --
        wodle = None
        for w in root.findall("wodle"):
            if w.get("name") == "command":
                wodle = w
                break
        
        if wodle is not None:
            # Check details
            cmd = wodle.find("command")
            tag = wodle.find("tag")
            if cmd is not None and cmd.text == "ss -tlnp" and tag is not None and tag.text == "listening-ports":
                score += 15
            else:
                feedback.append("Wodle command/tag incorrect.")
        else:
            feedback.append("Wodle command section missing.")

        # -- Verify Rootcheck (5 pts) --
        rootcheck = root.find("rootcheck")
        if rootcheck is not None:
            freq = rootcheck.find("frequency")
            if freq is not None and freq.text == "3600":
                score += 5
            else:
                feedback.append("Rootcheck frequency incorrect.")
        else:
            feedback.append("Rootcheck section missing.")

    except ET.ParseError:
        feedback.append("Configuration is NOT valid XML.")
    except Exception as e:
        feedback.append(f"Error parsing configuration: {str(e)}")

    passed = score >= 60 and result.get("group_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }