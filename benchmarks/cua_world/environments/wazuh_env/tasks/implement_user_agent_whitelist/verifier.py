#!/usr/bin/env python3
"""
Verifier for implement_user_agent_whitelist task.
"""

import json
import base64
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_user_agent_whitelist(traj, env_info, task_info):
    """
    Verifies that the agent correctly implemented the User-Agent whitelist.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from environment
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
    feedback_parts = []
    
    # Metadata requirements
    required_agents = task_info.get('metadata', {}).get('required_agents', [])
    required_rule_id = str(task_info.get('metadata', {}).get('rule_id', 100200))

    # Criterion 1: List Creation (20 pts)
    list_exists = result.get('list_exists', False)
    list_content_b64 = result.get('list_content_b64', "")
    
    if list_exists:
        try:
            list_content = base64.b64decode(list_content_b64).decode('utf-8')
            # Check for required agents
            missing = [ua for ua in required_agents if ua not in list_content]
            if not missing:
                score += 20
                feedback_parts.append("CDB list file created with correct content.")
            else:
                score += 10
                feedback_parts.append(f"CDB list created but missing agents: {', '.join(missing)}.")
        except:
            feedback_parts.append("Error decoding list content.")
    else:
        feedback_parts.append("CDB list file not found.")

    # Criterion 2: CDB Compilation (10 pts)
    cdb_exists = result.get('cdb_exists', False)
    cdb_newly_compiled = result.get('cdb_newly_compiled', False)
    
    if cdb_exists and cdb_newly_compiled:
        score += 10
        feedback_parts.append("CDB compiled successfully during task.")
    elif cdb_exists:
        score += 5
        feedback_parts.append("CDB exists but timestamp indicates it wasn't compiled during task.")
    else:
        feedback_parts.append("CDB binary file (.cdb) not found.")

    # Criterion 3: ossec.conf Configuration (20 pts)
    if result.get('ossec_conf_has_list', False):
        score += 20
        feedback_parts.append("ossec.conf configured to use the list.")
    else:
        feedback_parts.append("ossec.conf does not reference the list file.")

    # Criterion 4: Rule Creation & Logic (20 pts)
    rules_content_b64 = result.get('rules_content_b64', "")
    rule_found = False
    logic_correct = False
    
    if rules_content_b64:
        try:
            rules_content = base64.b64decode(rules_content_b64).decode('utf-8')
            if f'id="{required_rule_id}"' in rules_content or f'id="{required_rule_id}"' in rules_content:
                rule_found = True
                score += 10
                feedback_parts.append(f"Rule {required_rule_id} found.")
                
                # Check logic: look for negation operator and list usage
                # Common patterns: <list field="user_agent" lookup="not_match_key">
                if 'lookup="not_match_key"' in rules_content or 'lookup="not_match_as_key"' in rules_content:
                    if 'authorized_user_agents' in rules_content:
                        logic_correct = True
                        score += 10
                        feedback_parts.append("Rule logic (negation) appears correct.")
            else:
                feedback_parts.append(f"Rule ID {required_rule_id} not found in local_rules.xml.")
        except:
            feedback_parts.append("Error parsing local_rules.xml.")

    # Criterion 5: Functional Test (30 pts)
    # 20 pts for blocking bad UA, 10 pts for allowing good UA
    fired_bad = result.get('functional_test_fired_bad', False)
    fired_good = result.get('functional_test_fired_good', False)
    
    if fired_bad:
        score += 20
        feedback_parts.append("Functional test PASSED: Unauthorized User-Agent triggered alert.")
    else:
        feedback_parts.append("Functional test FAILED: Unauthorized User-Agent did NOT trigger alert.")
        
    if not fired_good:
        score += 10
        feedback_parts.append("Functional test PASSED: Authorized User-Agent did NOT trigger alert.")
    else:
        feedback_parts.append("Functional test FAILED: Authorized User-Agent triggered alert (False Positive).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }