#!/usr/bin/env python3
"""
Verifier for tune_rule_false_positives task.
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tune_rule_false_positives(traj, env_info, task_info):
    """
    Verify the agent correctly tuned Wazuh rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Extract data
    r5402 = result.get('rule_5402', {})
    r100100 = result.get('rule_100100', {})
    content = result.get('local_rules_content', '')
    manager_uptime = result.get('manager_uptime_sec', 999999)
    task_duration = result.get('task_end', 0) - result.get('task_start', 0)
    
    # ------------------------------------------------------------------
    # Check 1: Rule 5402 Override (Max 40 pts)
    # ------------------------------------------------------------------
    
    # 1a. Exists and Level is 0 (25 pts)
    if r5402.get('exists') and r5402.get('level') == 0:
        score += 25
        feedback.append("Rule 5402 correctly overridden to level 0.")
    elif r5402.get('exists'):
        feedback.append(f"Rule 5402 exists but level is {r5402.get('level')} (expected 0).")
    else:
        feedback.append("Rule 5402 not found in active ruleset.")

    # 1b. overwrite="yes" usage (10 pts)
    # Check XML content for this specific attribute on rule 5402
    if re.search(r'<rule\s+id="5402"\s+level="0"\s+overwrite="yes">', content) or \
       re.search(r'<rule\s+id="5402"\s+overwrite="yes"\s+level="0">', content) or \
       re.search(r'<rule\s+level="0"\s+overwrite="yes"\s+id="5402">', content):
        score += 10
        feedback.append("Used overwrite='yes' correctly.")
    else:
        # Fallback regex for less strict ordering
        if 'overwrite="yes"' in content and 'id="5402"' in content:
            score += 5
            feedback.append("Found overwrite='yes' but XML structure might be loose.")
        else:
            feedback.append("Did not find 'overwrite=\"yes\"' attribute for rule 5402.")

    # 1c. Logic preservation (5 pts)
    # Check for match pattern or if_sid in content
    if 'if_sid>5401<' in content.replace(" ", "") or 'if_sid>5401<' in content:
        score += 5
        feedback.append("Preserved if_sid 5401.")
    else:
        feedback.append("Missing if_sid 5401 in override.")

    # ------------------------------------------------------------------
    # Check 2: Rule 100100 Child Rule (Max 45 pts)
    # ------------------------------------------------------------------

    # 2a. Exists and Level is 0 (25 pts)
    if r100100.get('exists') and r100100.get('level') == 0:
        score += 25
        feedback.append("Rule 100100 correctly created with level 0.")
    elif r100100.get('exists'):
        feedback.append(f"Rule 100100 exists but level is {r100100.get('level')} (expected 0).")
    else:
        feedback.append("Rule 100100 not found in active ruleset.")

    # 2b. Parent is 5501 (10 pts)
    # We can check 'details' from API or regex the content
    # API details often hidden for custom rules depending on version, check content reliability
    if '<if_sid>5501</if_sid>' in content:
        score += 10
        feedback.append("Rule 100100 correctly triggers on parent 5501.")
    else:
        feedback.append("Rule 100100 does not appear to use if_sid 5501.")

    # 2c. Matches backup_svc (10 pts)
    if 'backup_svc' in content:
        score += 10
        feedback.append("Rule 100100 correctly matches 'backup_svc'.")
    else:
        feedback.append("Rule 100100 missing match for 'backup_svc'.")

    # ------------------------------------------------------------------
    # Check 3: Manager Restart & Validity (Max 15 pts)
    # ------------------------------------------------------------------

    # 3a. Manager restarted (10 pts)
    # If manager uptime is less than task duration (plus some buffer), it was restarted
    # If uptime is -1, it's not running
    if manager_uptime == -1:
        feedback.append("Wazuh manager is NOT running.")
    elif manager_uptime < (task_duration + 300): # generous buffer
        score += 10
        feedback.append("Wazuh manager was restarted.")
    else:
        feedback.append(f"Wazuh manager uptime ({manager_uptime}s) suggests no restart occurred during task.")

    # 3b. XML Validity (5 pts)
    # If the manager is running AND we see our rules in the API, the XML is valid.
    # If the manager crashed, this would fail.
    if manager_uptime != -1 and r5402.get('exists') and r100100.get('exists'):
        score += 5
        feedback.append("XML configuration is valid and loaded.")

    # Final logic
    passed = score >= 70 and r5402.get('level') == 0 and r100100.get('exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }