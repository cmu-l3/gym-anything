#!/usr/bin/env python3
"""
Verifier for Implement Custom Active Response task.

Verifies:
1. Live Fire Test (Did the file actually move?) - CRITICAL
2. Directory structure
3. FIM Configuration (ossec.conf)
4. Custom Rule (local_rules.xml)
5. Active Response Script (quarantine.sh)
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_custom_quarantine_ar(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    live_test = result.get('live_test', {})
    static = result.get('static_analysis', {})
    
    # Decode contents
    try:
        ossec_conf = base64.b64decode(static.get('ossec_conf_b64', '')).decode('utf-8', errors='ignore')
        rules_xml = base64.b64decode(static.get('rules_b64', '')).decode('utf-8', errors='ignore')
        script_content = base64.b64decode(static.get('script_content_b64', '')).decode('utf-8', errors='ignore')
    except:
        ossec_conf = ""
        rules_xml = ""
        script_content = ""

    # --- CRITERION 1: Directories (5 pts) ---
    if static.get('dir_contracts_exists') and static.get('dir_quarantine_exists'):
        score += 5
        feedback.append("Directories created successfully.")
    else:
        feedback.append("Failed to create required directories (/home/ga/contracts or /home/ga/quarantine).")

    # --- CRITERION 2: FIM Configuration (15 pts) ---
    # Look for /home/ga/contracts and realtime="yes" in ossec.conf
    fim_configured = False
    if "/home/ga/contracts" in ossec_conf and 'realtime="yes"' in ossec_conf:
        # Simple string check; ideally XML parsing, but grep-like is robust enough for presence
        fim_configured = True
        score += 15
        feedback.append("FIM real-time monitoring configured.")
    else:
        feedback.append("FIM configuration missing or not set to realtime for /home/ga/contracts.")

    # --- CRITERION 3: Custom Rule (20 pts) ---
    # Look for rule 100550 and path match
    rule_configured = False
    if 'id="100550"' in rules_xml and '/home/ga/contracts' in rules_xml:
        rule_configured = True
        score += 20
        feedback.append("Custom detection rule 100550 created.")
    else:
        feedback.append("Custom rule 100550 missing or does not reference the contracts directory.")

    # --- CRITERION 4: AR Script (25 pts) ---
    script_exists = static.get('script_exists', False)
    if script_exists:
        score += 10
        # Check permissions (should contain root:wazuh or 750/770)
        perms = static.get('script_perms', '')
        if "root:wazuh" in perms or "wazuh" in perms: # Flexible on exact ownership if it works
            score += 5
        
        # Check logic (very basic check for 'mv' and 'suspect')
        if "mv" in script_content and ".suspect" in script_content:
            score += 10
            feedback.append("Quarantine script created with correct logic.")
        else:
            feedback.append("Quarantine script exists but logic seems incorrect (missing mv or .suspect).")
    else:
        feedback.append("Quarantine script not found at /var/ossec/active-response/bin/quarantine.sh.")

    # --- CRITERION 5: Manager Config for AR (15 pts) ---
    # Look for <command> and <active-response> linking to rule 100550
    ar_configured = False
    if '<active-response>' in ossec_conf and '100550' in ossec_conf:
        ar_configured = True
        score += 15
        feedback.append("Active Response block configured in ossec.conf.")
    else:
        feedback.append("Active Response configuration missing in ossec.conf.")

    # --- CRITERION 6: LIVE FIRE TEST (20 pts) ---
    if live_test.get('passed', False):
        score += 20
        feedback.append("LIVE TEST PASSED: File was successfully quarantined!")
    else:
        feedback.append("LIVE TEST FAILED: File was not moved to quarantine automatically.")
        if live_test.get('source_removed'):
            feedback.append("(Source file was removed, but destination not found?)")
        elif not live_test.get('source_removed'):
            feedback.append("(Source file remained in folder - AR did not trigger).")

    # Pass/Fail logic
    # Must have passed live test OR (have all components correct but maybe minor syntax error prevented trigger)
    # But for "hard" task, we expect it to work.
    # We set pass threshold at 70, which effectively requires the Live Test (20) + most other things,
    # OR perfect configuration (80) even if live test failed due to timing/environment glitch.
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }