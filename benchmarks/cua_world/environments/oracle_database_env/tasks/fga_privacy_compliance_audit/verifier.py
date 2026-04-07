#!/usr/bin/env python3
"""
Verifier for FGA Privacy Compliance Audit.

Verification Strategy:
1. Programmatic Check (Policy Config):
   - Policy exists?
   - Condition matches 'SALARY >= 15000'?
   - Columns include SALARY/EMAIL/PHONE?
   - Enabled?
2. Functional Check (The "Gold Standard"):
   - Did the export script's test query (SELECT salary FROM employees WHERE id=100)
     actually cause the audit trail count to increase? 
     This proves the policy actually works as intended regardless of syntax variations.
3. Evidence Check:
   - Did the agent export a CSV proof file?

Pass Threshold: 65 points (Must have working policy).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fga_compliance(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- 1. Policy Existence (20 pts) ---
    if result.get("policy_exists"):
        score += 20
        feedback_parts.append("Policy 'AUDIT_VIP_ACCESS' created (+20)")
    else:
        return {"passed": False, "score": 0, "feedback": "Policy 'AUDIT_VIP_ACCESS' not found"}

    details = result.get("policy_details", {})
    
    # --- 2. Condition Logic (20 pts) ---
    condition = details.get("condition_text", "").upper() if details.get("condition_text") else ""
    # Look for key elements: SALARY and 15000 (allowing formatting)
    if "SALARY" in condition and ("15000" in condition or "15,000" in condition) and (">" in condition):
        score += 20
        feedback_parts.append("Audit condition looks correct (+20)")
    else:
        feedback_parts.append(f"Audit condition '{condition}' may be incorrect (Expected SALARY >= 15000)")
        # Partial credit if just numbers match
        if "15000" in condition:
            score += 10
            feedback_parts.append("Partial credit for correct threshold value (+10)")

    # --- 3. Column Scope (15 pts) ---
    columns = details.get("columns", "").upper() if details.get("columns") else ""
    # Expected: SALARY, EMAIL, PHONE_NUMBER
    required_cols = ["SALARY", "EMAIL", "PHONE"] # partial match for PHONE_NUMBER
    found_cols = [c for c in required_cols if c in columns]
    
    if len(found_cols) == 3:
        score += 15
        feedback_parts.append("Correct sensitive columns targeted (+15)")
    elif len(found_cols) > 0:
        score += 5 * len(found_cols)
        feedback_parts.append(f"Partial columns matched (+{5*len(found_cols)})")
    else:
        feedback_parts.append("No required columns found in policy columns")

    # --- 4. Policy Enabled (10 pts) ---
    if details.get("enabled") == "YES":
        score += 10
        feedback_parts.append("Policy is enabled (+10)")
    else:
        feedback_parts.append("Policy is disabled")

    # --- 5. Functional Verification (10 pts) ---
    # Did the test query actually generate an audit record?
    if result.get("functional_test_passed"):
        score += 10
        feedback_parts.append("Functional test passed: Audit triggered by executive query (+10)")
    else:
        feedback_parts.append("Functional test failed: Policy did not log the test query")

    # --- 6. Evidence File (15 pts) ---
    if result.get("evidence_file_exists") and result.get("evidence_file_valid"):
        score += 15
        feedback_parts.append("Evidence CSV file exported correctly (+15)")
    elif result.get("evidence_file_exists"):
        score += 5
        feedback_parts.append("Evidence file exists but format invalid (+5)")
    else:
        feedback_parts.append("Evidence file not found")
        
    # --- 7. Correct Statement Type (10 pts) ---
    if details.get("audit_select") == "YES":
        score += 10
        feedback_parts.append("SELECT statements audited (+10)")

    passed = score >= 65 and result.get("policy_exists")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }