#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_data_staging_activity(traj, env_info, task_info):
    """
    Verify the Wazuh data staging detection task.
    
    Criteria:
    1. Rule 100250 exists in local_rules.xml (20 pts)
    2. Rule level is 10 (10 pts)
    3. Rule matches 'tar' and path (static check) (10 pts)
    4. Rule triggers on malicious log (via wazuh-logtest) (40 pts)
    5. Rule ignores benign log (via wazuh-logtest) (20 pts)
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
    
    # 1. Rule Existence (20 pts)
    if result.get("rule_exists", False):
        score += 20
        feedback.append("Rule 100250 created.")
    else:
        feedback.append("Rule 100250 NOT found in local_rules.xml.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. Rule Level (10 pts)
    level = result.get("rule_level", "0")
    if str(level) == "10":
        score += 10
        feedback.append("Correct alert level (10).")
    else:
        feedback.append(f"Incorrect alert level: {level} (expected 10).")

    # 3. Static Content Check (10 pts)
    if result.get("contains_tar", False) and result.get("contains_path", False):
        score += 10
        feedback.append("Rule content contains required keywords.")
    else:
        feedback.append("Rule missing 'tar' or path keywords.")

    # 4. Functional Test: Malicious Log (40 pts)
    if result.get("detects_malicious", False):
        score += 40
        feedback.append("Successfully detected malicious data staging activity.")
    else:
        feedback.append("Failed to trigger on malicious log sample.")

    # 5. Functional Test: Benign Log (20 pts)
    if result.get("ignores_benign", False):
        score += 20
        feedback.append("Correctly ignored benign activity.")
    else:
        feedback.append("False positive detected: Rule triggered on benign activity.")

    passed = score >= 70 and result.get("detects_malicious", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }