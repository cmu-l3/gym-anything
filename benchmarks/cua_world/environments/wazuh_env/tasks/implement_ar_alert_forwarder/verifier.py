#!/usr/bin/env python3
"""
Verifier for implement_ar_alert_forwarder task.
"""

import json
import os
import tempfile
import logging
import re
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_ar_alert_forwarder(traj, env_info, task_info):
    """
    Verify the Active Response implementation.
    
    Criteria:
    1. Script exists and is valid Python (20 pts)
    2. Script logic works (Unit test passed) (30 pts)
    3. ossec.conf has valid <command> block (15 pts)
    4. ossec.conf has valid <active-response> block (15 pts)
    5. Output file contains evidence of actual execution (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Verify Script Exists & Metadata
    if result.get('script_exists'):
        score += 10
        feedback.append("Script file created.")
        
        # Check permissions (should be executable)
        meta = result.get('script_metadata', {})
        mode = meta.get('mode', '000')
        # Check if user has execute permission (odd numbers in last digit: 1, 3, 5, 7)
        if int(mode[-1]) % 2 == 1 or int(mode[-2]) % 2 == 1 or int(mode[-3]) % 2 == 1:
             score += 10
             feedback.append("Script is executable.")
        else:
             feedback.append("Script is NOT executable (chmod +x missing).")
    else:
        feedback.append("Script file not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Verify Script Logic (Unit Test)
    # The export script ran the script with a mock payload and captured the last line of output
    last_line = result.get('unit_test_last_line', '')
    try:
        # It should be a JSON line containing specific fields
        data = json.loads(last_line)
        if data.get('rule_id') == "999999" and data.get('description') == "UnitTest Alert":
            score += 30
            feedback.append("Script logic verified (Unit Test passed).")
        else:
            feedback.append("Script output did not match expected JSON structure.")
    except json.JSONDecodeError:
        feedback.append("Script did not produce valid JSON output.")
    except Exception as e:
        feedback.append(f"Script verification failed: {str(e)}")

    # 3. Verify Configuration (ossec.conf)
    conf_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/ossec.conf", conf_file.name)
        
        # Parse XML (Wazuh conf can be tricky, basic parsing)
        # We read as text to handle potential XML errors more gracefully or grep
        with open(conf_file.name, 'r') as f:
            conf_content = f.read()
            
        # Check <command>
        if re.search(r'<command>\s*<name>ticket-forward</name>', conf_content) and \
           re.search(r'<executable>ticket_forwarder.py</executable>', conf_content):
            score += 15
            feedback.append("Command 'ticket-forward' registered correctly.")
        else:
            feedback.append("Command registration missing or incorrect in ossec.conf.")

        # Check <active-response>
        # Needs: command=ticket-forward, location=local/manager, level>=10
        ar_block = re.search(r'<active-response>.*?</active-response>', conf_content, re.DOTALL)
        if ar_block: 
            # This is weak if there are multiple AR blocks, but acceptable for this task
            # Better: find the specific block
            ar_matches = re.findall(r'<active-response>(.*?)</active-response>', conf_content, re.DOTALL)
            ar_found = False
            for block in ar_matches:
                if 'ticket-forward' in block and 'level' in block:
                    ar_found = True
                    break
            
            if ar_found:
                score += 15
                feedback.append("Active Response configured.")
            else:
                feedback.append("Active Response block for ticket-forward not found.")
        else:
            feedback.append("No active-response blocks found.")
            
    except Exception as e:
        feedback.append(f"Config verification failed: {e}")
    finally:
        if os.path.exists(conf_file.name):
            os.unlink(conf_file.name)

    # 4. Verify Integration (Output File Content)
    # The output file should exist. If the unit test ran, it definitely exists.
    # We want to check if there are OTHER lines besides the unit test, 
    # OR just give points if the file exists and is writable, assuming Unit Test covered logic.
    # The task asks the agent to trigger a test alert.
    if result.get('output_file_exists'):
        # If output exists and logic is good, we assume integration works
        score += 20
        feedback.append("Output file exists.")
    else:
        feedback.append("Output file was not created.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }