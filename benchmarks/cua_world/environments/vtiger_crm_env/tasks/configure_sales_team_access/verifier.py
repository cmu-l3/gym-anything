#!/usr/bin/env python3
"""
Verifier for configure_sales_team_access task.

Validates the end-to-end access control configuration in Vtiger CRM:
1. Profile created with correct restrictive and permissive module settings
2. Role created within the proper place in the hierarchy and linked to the profile
3. User created with correct credentials/details and linked to the role

Score breakdown (Total 100):
- Profile exists: 8 pts
- Invoice disabled: 8 pts
- SalesOrder disabled: 8 pts
- PurchaseOrder disabled: 8 pts
- Core modules (Contacts/Accounts/Potentials/Leads) enabled: 8 pts
- Role exists: 8 pts
- Role subordinate to Sales Person: 10 pts
- Role linked to Profile: 8 pts
- User exists: 8 pts
- User names match: 5 pts
- User email matches: 5 pts
- User is not admin: 6 pts
- User assigned to Role: 10 pts
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sales_team_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    # Retrieve exported json
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_sales_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    profile = result.get("profile")
    role = result.get("role")
    user = result.get("user")
    parent_role_id = result.get("parent_role_id")

    # Anti-gaming: Ensure counts actually increased (records weren't pre-existing)
    init_c = result.get("initial_counts", {})
    final_c = result.get("final_counts", {})
    if final_c.get("profiles", 0) <= init_c.get("profiles", 0):
        feedback_parts.append("Warning: Total Profile count did not increase.")
    if final_c.get("users", 0) <= init_c.get("users", 0):
        feedback_parts.append("Warning: Total User count did not increase.")

    # 1. Profile Checks
    if profile:
        score += 8
        feedback_parts.append("✅ Profile 'Junior Sales Access' created")
        
        perms = profile.get("permissions", {})
        # Note: In Vtiger DB, permissions '0' means Enabled/Visible, '1' means Disabled/Hidden
        
        # Disabled modules
        if perms.get("Invoice") == "1":
            score += 8
            feedback_parts.append("✅ Invoice module restricted")
        else:
            feedback_parts.append("❌ Invoice module is not restricted")
            
        if perms.get("SalesOrder") == "1":
            score += 8
            feedback_parts.append("✅ SalesOrder module restricted")
        else:
            feedback_parts.append("❌ SalesOrder module is not restricted")
            
        if perms.get("PurchaseOrder") == "1":
            score += 8
            feedback_parts.append("✅ PurchaseOrder module restricted")
        else:
            feedback_parts.append("❌ PurchaseOrder module is not restricted")
            
        # Core enabled modules (Organizations is 'Accounts', Opportunities is 'Potentials' in DB)
        core_enabled = all([
            perms.get("Contacts") == "0",
            perms.get("Accounts") == "0",
            perms.get("Leads") == "0",
            perms.get("Potentials") == "0"
        ])
        if core_enabled:
            score += 8
            feedback_parts.append("✅ Core CRM modules remained enabled")
        else:
            feedback_parts.append("❌ Core modules were improperly disabled")
    else:
        feedback_parts.append("❌ Profile 'Junior Sales Access' not found")

    # 2. Role Checks
    if role:
        score += 8
        feedback_parts.append("✅ Role 'Junior Sales Rep' created")
        
        # Check hierarchy
        # Vtiger parentrole string format: "H1::H2::...::CurrentRoleID"
        if parent_role_id and parent_role_id in role.get("parentrole", ""):
            score += 10
            feedback_parts.append("✅ Role correctly placed subordinate to 'Sales Person'")
        else:
            feedback_parts.append("❌ Role hierarchy is incorrect (not subordinate to Sales Person)")
            
        # Check profile link
        if profile and role.get("linked_profileid") == profile.get("profileid"):
            score += 8
            feedback_parts.append("✅ Role successfully linked to the Junior Sales Access profile")
        else:
            feedback_parts.append("❌ Role is not linked to the correct profile")
    else:
        feedback_parts.append("❌ Role 'Junior Sales Rep' not found")

    # 3. User Checks
    if user:
        score += 8
        feedback_parts.append("✅ User 'sarah.mitchell' created")
        
        # Details
        if user.get("first_name", "").lower() == "sarah" and user.get("last_name", "").lower() == "mitchell":
            score += 5
            feedback_parts.append("✅ User first and last names correct")
        else:
            feedback_parts.append("❌ User name is incorrect")
            
        if user.get("email1", "").lower() == "sarah.mitchell@greenfield-dist.com":
            score += 5
            feedback_parts.append("✅ User email correct")
        else:
            feedback_parts.append("❌ User email is incorrect")
            
        # Security checks
        is_admin_flag = str(user.get("is_admin", "")).lower()
        if is_admin_flag in ["off", "0", "false"]:
            score += 6
            feedback_parts.append("✅ User correctly established as non-admin")
        else:
            feedback_parts.append("❌ User was accidentally given Admin access")
            
        # Check role assignment
        if role and user.get("linked_roleid") == role.get("roleid"):
            score += 10
            feedback_parts.append("✅ User assigned to 'Junior Sales Rep' role successfully")
        else:
            feedback_parts.append("❌ User is missing correct role assignment")
    else:
        feedback_parts.append("❌ User 'sarah.mitchell' not found")

    # Final pass logic (Threshold: 60, but requires all 3 base objects to exist)
    all_objects_created = bool(profile and role and user)
    passed = score >= 60 and all_objects_created

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }