#!/usr/bin/env python3
"""
Verifier for configure_report_acl task.

Scoring Criteria:
1. Group 'SUP_SECURE' exists (20 pts)
2. Granular Mode Enabled (allowed_reports != 'ALL') (20 pts)
3. Whitelisted: 'Agent Performance Detail' included (20 pts)
4. Whitelisted: 'Real-Time Main Report' included (20 pts)
5. Blacklisted: No 'export' scripts allowed (10 pts)
6. Security: force_change_password == 'Y' (10 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_report_acl(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    group_exists = result.get("group_exists", False)
    config = result.get("config", {})
    allowed_reports = config.get("allowed_reports", "")
    force_pwd = config.get("force_change_password", "N")
    
    # Metadata requirements
    required_reports = task_info.get("metadata", {}).get("required_reports", 
        ["AST_agent_performance_detail.php", "AST_timeonVDADall.php"])
    forbidden_keyword = task_info.get("metadata", {}).get("forbidden_keyword", "export")

    score = 0
    feedback_parts = []
    
    # CRITERION 1: Group Exists (20 pts)
    if group_exists:
        score += 20
        feedback_parts.append("Group 'SUP_SECURE' created.")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "User Group 'SUP_SECURE' was not found in the database."
        }

    # CRITERION 2: Granular Mode (20 pts)
    # If allowed_reports is "ALL", they failed to restrict.
    if allowed_reports.strip() == "ALL":
        feedback_parts.append("Failed: Allowed Reports is set to 'ALL' (Granular access not configured).")
    elif allowed_reports.strip() == "":
        feedback_parts.append("Failed: Allowed Reports is empty/NONE.")
    else:
        score += 20
        feedback_parts.append("Granular report access enabled.")

    # CRITERION 3 & 4: Whitelist Checks (20 pts each)
    # The string contains space-separated PHP script names
    reports_list = allowed_reports.split()
    
    # Check Agent Performance Detail
    if "AST_agent_performance_detail.php" in reports_list:
        score += 20
        feedback_parts.append("Agent Performance Detail allowed.")
    else:
        feedback_parts.append("Missing: Agent Performance Detail.")

    # Check Real-Time Main Report
    if "AST_timeonVDADall.php" in reports_list:
        score += 20
        feedback_parts.append("Real-Time Main Report allowed.")
    else:
        feedback_parts.append("Missing: Real-Time Main Report.")

    # CRITERION 5: Blacklist Check (10 pts)
    # Ensure no script containing "export" is in the list
    exports_found = [r for r in reports_list if forbidden_keyword.lower() in r.lower()]
    if not exports_found:
        score += 10
        feedback_parts.append("Export capabilities successfully blocked.")
    else:
        feedback_parts.append(f"Security Violation: Export reports found ({len(exports_found)} allowed).")

    # CRITERION 6: Password Policy (10 pts)
    if force_pwd == "Y":
        score += 10
        feedback_parts.append("Force Password Change enabled.")
    else:
        feedback_parts.append("Force Password Change not set to Y.")

    # Final Verification
    passed = score >= 80  # Threshold allows for minor config error but requires core security logic
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }