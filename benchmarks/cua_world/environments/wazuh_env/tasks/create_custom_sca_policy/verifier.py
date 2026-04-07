#!/usr/bin/env python3
"""
Verifier for create_custom_sca_policy task.
"""

import json
import base64
import yaml
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_sca_policy(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Policy File Exists & Created During Task (20 pts)
    if result.get("policy_exists"):
        score += 10
        feedback.append("Policy file created.")
        if result.get("created_during_task"):
            score += 10
            feedback.append("Policy file created during task window.")
        else:
            feedback.append("Policy file timestamp is old (pre-existing?).")
    else:
        return {"passed": False, "score": 0, "feedback": "Policy file payment_gateway_audit.yml not found."}

    # 2. Analyze Policy Content (50 pts total)
    try:
        policy_yaml = yaml.safe_load(base64.b64decode(result.get("policy_content_b64", "")))
        
        # Check Metadata (10 pts)
        if str(policy_yaml.get("policy", {}).get("id")) == "10005":
            score += 5
            feedback.append("Policy ID is correct (10005).")
        else:
            feedback.append(f"Incorrect Policy ID: {policy_yaml.get('policy', {}).get('id')}")

        if "Payment Gateway Hardening" in policy_yaml.get("policy", {}).get("name", ""):
            score += 5
            feedback.append("Policy Name is correct.")
        
        # Check Rules (40 pts)
        checks = policy_yaml.get("checks", [])
        check_map = {str(c.get("id")): c for c in checks}

        # Check 10006: Permissions 400
        c1 = check_map.get("10006")
        if c1:
            rules = str(c1.get("rules", "")) + str(c1.get("condition", ""))
            # Look for permission check logic usually formatted as 'p:^400$' or similar
            if "400" in rules:
                score += 13
                feedback.append("Check 10006 logic found (400 permissions).")
            else:
                feedback.append("Check 10006 exists but missing '400' permission logic.")
        else:
            feedback.append("Check 10006 missing.")

        # Check 10007: Owner root
        c2 = check_map.get("10007")
        if c2:
            rules = str(c2.get("rules", "")) + str(c2.get("condition", ""))
            if "root" in rules:
                score += 13
                feedback.append("Check 10007 logic found (root owner).")
            else:
                feedback.append("Check 10007 exists but missing 'root' ownership logic.")
        else:
            feedback.append("Check 10007 missing.")

        # Check 10008: Content debug=false
        c3 = check_map.get("10008")
        if c3:
            rules = str(c3.get("rules", "")) + str(c3.get("condition", ""))
            if "debug=false" in rules:
                score += 14
                feedback.append("Check 10008 logic found (debug=false).")
            else:
                feedback.append("Check 10008 exists but missing 'debug=false' content logic.")
        else:
            feedback.append("Check 10008 missing.")

    except Exception as e:
        feedback.append(f"Failed to parse policy YAML: {e}")

    # 3. Check Configuration Update (15 pts)
    config_content = base64.b64decode(result.get("config_content_b64", "")).decode('utf-8', errors='ignore')
    if "etc/sca/payment_gateway_audit.yml" in config_content:
        score += 15
        feedback.append("ossec.conf updated with new policy path.")
    else:
        feedback.append("ossec.conf does not reference payment_gateway_audit.yml.")

    # 4. Check API/Execution (15 pts)
    # The API result should contain data for policy 10005 if it loaded successfully
    api_data = result.get("api_result", {})
    if api_data and str(api_data.get("policy_id")) == "10005":
        score += 15
        feedback.append("API confirms policy 10005 is loaded and running.")
        
        # Bonus: Check if it actually detected the fails we set up
        # We don't penalize strict correctness of pass/fail here as long as it ran,
        # but it's good confirmation.
        fail_count = api_data.get("fail", 0)
        if fail_count > 0:
            feedback.append(f"Policy successfully detected {fail_count} failures.")
    else:
        feedback.append("API verification failed (Policy not loaded or API unreachable).")

    # 5. Service Status
    if not result.get("manager_running"):
        score = 0
        feedback.append("CRITICAL: Wazuh manager is not running.")

    # Final logic
    passed = score >= 70 and result.get("manager_running")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }