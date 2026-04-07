#!/usr/bin/env python3
"""
Verifier for VPD Tenant Isolation Task.

Criteria:
1. VPD Policy exists on the target table (20 pts)
2. CLINIC_NORTH_APP sees exactly 35 rows (20 pts)
3. CLINIC_SOUTH_APP sees exactly 42 rows (20 pts)
4. SAAS_ADMIN sees all 100 rows (15 pts)
5. Dynamic Test: A newly created user mapped to a new clinic sees only their data (15 pts)
   - This prevents hardcoding user names in the policy logic.
6. Audit file exists (10 pts)

Pass Threshold: 75/100
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vpd_isolation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy result file
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "vpd_result.json")
        try:
            copy_from_env("/tmp/vpd_result.json", result_path)
            with open(result_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to retrieve verification results: {str(e)}"
            }
            
    score = 0
    feedback_parts = []
    
    # 1. Check Policy Existence (20 pts)
    if result.get("policy_exists"):
        score += 20
        details = result.get("policy_details", {})
        feedback_parts.append(f"Policy '{details.get('name')}' active on table (+20)")
    else:
        feedback_parts.append("No active VPD policy found on SAAS_CORE.PATIENT_ENCOUNTERS (0 pts)")
        
    # 2. Check North Count (20 pts)
    north_count = result.get("north_count")
    if north_count == 35:
        score += 20
        feedback_parts.append("North Clinic visibility correct (35 rows) (+20)")
    else:
        feedback_parts.append(f"North Clinic visibility incorrect: saw {north_count} rows, expected 35")
        
    # 3. Check South Count (20 pts)
    south_count = result.get("south_count")
    if south_count == 42:
        score += 20
        feedback_parts.append("South Clinic visibility correct (42 rows) (+20)")
    else:
        feedback_parts.append(f"South Clinic visibility incorrect: saw {south_count} rows, expected 42")
        
    # 4. Check Admin Count (15 pts)
    admin_count = result.get("admin_count")
    if admin_count == 100:
        score += 15
        feedback_parts.append("Admin visibility correct (100 rows) (+15)")
    else:
        feedback_parts.append(f"Admin visibility incorrect: saw {admin_count} rows, expected 100")
        
    # 5. Dynamic Test (15 pts)
    if result.get("dynamic_test_passed"):
        score += 15
        feedback_parts.append("Dynamic anti-gaming test passed (policy handles new users correctly) (+15)")
    else:
        details = result.get("dynamic_test_details", "Unknown failure")
        feedback_parts.append(f"Dynamic anti-gaming test failed: {details}")

    # 6. Audit File (10 pts)
    # Check via file listing in result or separate check? 
    # The export script didn't explicitly check file content to JSON, but the task described verifying it.
    # Let's check simply if the task output implied existence. 
    # Actually, let's look for the file directly if needed, but since we didn't export it in JSON,
    # we'll assume the verifier logic above covers the core requirements.
    # To follow the design strictly, I will check for the file using a separate copy if needed, 
    # or rely on the agent creating it. The export script checked existence but didn't put it in JSON keys explicitly.
    # I'll update the scoring to be robust without it or assume 0 if not tracked, 
    # but to be fair let's check if the file was created.
    
    # Let's perform a quick check for the audit file using copy_from_env as a fallback
    audit_file_path = os.path.join(tmpdir, "isolation_audit.txt")
    audit_exists = False
    try:
        copy_from_env("/home/ga/Desktop/isolation_audit.txt", audit_file_path)
        if os.path.exists(audit_file_path) and os.path.getsize(audit_file_path) > 0:
            audit_exists = True
    except:
        pass
        
    if audit_exists:
        score += 10
        feedback_parts.append("Audit report file found (+10)")
    else:
        feedback_parts.append("Audit report file not found or empty (0 pts)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }