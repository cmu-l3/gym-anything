#!/usr/bin/env python3
"""
Verifier for GDPR Row-Level Security Task.
Checks if the user, role, and security policy were created and if the data visibility is correctly restricted.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gdpr_row_level_security(traj, env_info, task_info):
    """
    Verify the RLS configuration.
    
    Criteria:
    1. User 'us_partner' exists and is assigned to 'us_analytics' role.
    2. Security Policy 'us_only_policy' exists.
    3. Policy contains correct predicate (Nationality = 'American').
    4. Policy is active on the Profiles class.
    5. CRITICAL: 'us_partner' can query Profiles but sees ONLY American records.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    data = result.get("verification_data", {})
    score = 0
    feedback = []
    
    # 1. Check User and Role (20 pts)
    if data.get("user_exists"):
        score += 10
        feedback.append("User 'us_partner' exists.")
    else:
        feedback.append("User 'us_partner' NOT found.")

    if data.get("role_exists"):
        score += 10
        feedback.append("Role 'us_analytics' exists and assigned.")
    else:
        feedback.append("Role 'us_analytics' NOT found or not assigned to user.")

    # 2. Check Policy Config (20 pts)
    if data.get("policy_exists"):
        score += 10
        feedback.append("Security Policy 'us_only_policy' exists.")
        
        predicate = data.get("policy_predicate", "")
        if "Nationality" in predicate and "American" in predicate:
            score += 10
            feedback.append("Policy predicate looks correct.")
        else:
            feedback.append(f"Policy predicate incorrect. Found: {predicate}")
    else:
        feedback.append("Security Policy NOT found.")

    # 3. Check Policy Application (10 pts)
    if data.get("policy_applied"):
        score += 10
        feedback.append("Policy is correctly applied to Profiles class.")
    else:
        feedback.append("Policy is NOT applied to Profiles class for the role.")

    # 4. Functional Verification (50 pts)
    # Did login work?
    if data.get("partner_login_success"):
        row_count = data.get("partner_row_count", 0)
        
        # Did they see data? (Should see at least 1 American)
        if row_count > 0:
            # Check for data leakage
            if data.get("all_partner_rows_are_american"):
                score += 40
                feedback.append(f"Success: Partner sees only American profiles ({row_count} records).")
                
                # Bonus check: did they see FEWER rows than root? (Proof filtering happened)
                if data.get("partner_sees_subset"):
                    score += 10
                    feedback.append("Filtering verified (Partner sees subset of total data).")
                else:
                    feedback.append("Warning: Partner sees same count as Root (Are there only Americans in DB?).")
            else:
                feedback.append("FAIL: Data Leakage! Partner sees non-American profiles.")
        else:
            feedback.append("FAIL: Partner sees 0 rows. Policy might be too restrictive or incorrect.")
    else:
        feedback.append("FAIL: Could not log in as 'us_partner' to verify data.")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }