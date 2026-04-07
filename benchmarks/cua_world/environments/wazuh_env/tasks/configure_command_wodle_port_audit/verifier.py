#!/usr/bin/env python3
"""
Verifier for configure_command_wodle_port_audit task.

Verifies:
1. ossec.conf contains a valid <wodle name="command"> block.
2. The block has the correct parameters (command, interval, tag, etc.).
3. The Wazuh manager is running and healthy.
4. Logs show evidence of the module starting/executing.
"""

import json
import os
import xml.etree.ElementTree as ET
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_command_wodle(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Files to retrieve
    files_to_copy = {
        "result": "/tmp/task_result.json",
        "config": "/tmp/final_ossec.conf",
        "logs": "/tmp/wodle_logs.txt"
    }
    
    local_files = {}
    
    # Create temp files and copy data
    try:
        for key, remote_path in files_to_copy.items():
            tf = tempfile.NamedTemporaryFile(delete=False)
            local_files[key] = tf.name
            tf.close() # Close so copy_from_env can write to it
            try:
                copy_from_env(remote_path, local_files[key])
            except Exception as e:
                logger.warning(f"Could not copy {remote_path}: {e}")
                local_files[key] = None

        # Load metadata
        if not local_files["result"]:
             return {"passed": False, "score": 0, "feedback": "Failed to retrieve task result data"}
             
        with open(local_files["result"], 'r') as f:
            result_data = json.load(f)

        # ---------------------------------------------------------
        # Criterion 1: Manager Health (10 pts)
        # ---------------------------------------------------------
        if result_data.get("manager_running", False):
            score += 10
            feedback_parts.append("Manager is running")
        else:
            feedback_parts.append("Manager is NOT running (critical failure)")
            
        # ---------------------------------------------------------
        # Criterion 2: Configuration Modification (5 pts)
        # ---------------------------------------------------------
        if result_data.get("config_modified", False):
            score += 5
            feedback_parts.append("Configuration file was modified")
        else:
            feedback_parts.append("Configuration file was NOT modified")
            # If config wasn't touched, likely failed
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        # ---------------------------------------------------------
        # Criterion 3: XML Configuration Analysis (60 pts total)
        # ---------------------------------------------------------
        config_path = local_files["config"]
        valid_xml = False
        wodle_found = False
        
        if config_path and os.path.exists(config_path):
            try:
                # Wazuh configs often have multiple root elements or comments that might confuse strict parsers
                # But ossec.conf usually has <ossec_config> as root.
                tree = ET.parse(config_path)
                root = tree.getroot()
                valid_xml = True
                score += 5 # Valid XML structure
                
                # Find the command wodle
                # It should look like <wodle name="command">...</wodle>
                target_wodle = None
                for wodle in root.findall(".//wodle"):
                    if wodle.get("name") == "command":
                        # Check if it's the right one by looking at the tag or command
                        cmd_elem = wodle.find("command")
                        tag_elem = wodle.find("tag")
                        
                        cmd_text = cmd_elem.text.strip() if cmd_elem is not None and cmd_elem.text else ""
                        tag_text = tag_elem.text.strip() if tag_elem is not None and tag_elem.text else ""
                        
                        if "ss -tlnp" in cmd_text or "netstat -tlnp" in cmd_text or "port-audit" in tag_text:
                            target_wodle = wodle
                            wodle_found = True
                            break
                
                if wodle_found and target_wodle is not None:
                    score += 15
                    feedback_parts.append("Command wodle block found")
                    
                    # Check Attributes
                    # Command (15 pts)
                    cmd = target_wodle.find("command")
                    if cmd is not None and ("ss -tlnp" in cmd.text or "netstat -tlnp" in cmd.text):
                        score += 15
                        feedback_parts.append("Correct command")
                    else:
                        feedback_parts.append("Incorrect or missing command")

                    # Interval (15 pts) - accept 300 or 5m
                    interval = target_wodle.find("interval")
                    if interval is not None and (interval.text.strip() == "300" or interval.text.strip() == "5m"):
                        score += 15
                        feedback_parts.append("Correct interval")
                    else:
                        feedback_parts.append("Incorrect interval (expected 300)")

                    # Tag (10 pts)
                    tag = target_wodle.find("tag")
                    if tag is not None and tag.text.strip() == "port-audit":
                        score += 15
                        feedback_parts.append("Correct tag")
                    else:
                        feedback_parts.append("Incorrect tag")
                        
                    # Minor settings (Run on start, timeout, ignore output) - 5 pts each
                    run_start = target_wodle.find("run_on_start")
                    if run_start is not None and run_start.text.strip() == "yes":
                        score += 5
                        
                    timeout = target_wodle.find("timeout")
                    if timeout is not None and timeout.text.strip() == "30":
                        score += 5
                        
                    ignore = target_wodle.find("ignore_output")
                    if ignore is not None and ignore.text.strip() == "no":
                        score += 5

                else:
                    feedback_parts.append("No matching <wodle name='command'> block found")

            except ET.ParseError:
                feedback_parts.append("ossec.conf is not valid XML")
            except Exception as e:
                feedback_parts.append(f"Error parsing config: {str(e)}")
        else:
            feedback_parts.append("Could not read configuration file")

        # ---------------------------------------------------------
        # Criterion 4: Log Evidence (10 pts)
        # ---------------------------------------------------------
        log_path = local_files["logs"]
        log_evidence = False
        if log_path and os.path.exists(log_path):
            with open(log_path, 'r') as f:
                log_content = f.read()
                # Look for evidence that the module started or ran
                # Typical log: "wazuh-modulesd:command: INFO: Starting command 'ss -tlnp'."
                if "port-audit" in log_content or ("Starting command" in log_content and "ss -tlnp" in log_content):
                    log_evidence = True
        
        if log_evidence:
            score += 10
            feedback_parts.append("Log evidence of execution found")
        else:
            feedback_parts.append("No log evidence of execution found")

    finally:
        # Cleanup temp files
        for path in local_files.values():
            if path and os.path.exists(path):
                os.unlink(path)

    # Normalize score to 100 max (current potential max is > 100 if we sum everything, let's clamp)
    # Breakdown:
    # Manager Running: 10
    # Config Modified: 5
    # Valid XML: 5
    # Wodle Found: 15
    # Command: 15
    # Interval: 15
    # Tag: 15
    # Minor settings (3*5): 15
    # Log Evidence: 10
    # Total potential: 105. 
    # Let's cap at 100.
    
    final_score = min(100, score)
    passed = final_score >= 60 and wodle_found and result_data.get("manager_running", False)

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }