#!/usr/bin/env python3
"""Verifier for Admin Role & User task in Magento.

Task: Create a restricted admin role 'Customer Service Lead' and an admin user
'cs_lead_jones' assigned to it.

Criteria:
1. Role exists (20 pts)
2. Permissions are restricted correctly (Custom, not All) (15 pts)
3. Allowed: Sales, Customers, Dashboard (15 + 15 + 5 pts)
4. Denied: Catalog, System/Config (10 pts)
5. User exists with correct details (10 pts)
6. User assigned to correct role (10 pts)

Pass threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_admin_role_user(traj, env_info, task_info):
    """
    Verify admin role creation and user assignment.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_role = metadata.get('expected_role_name', 'Customer Service Lead')
    expected_user = metadata.get('expected_username', 'cs_lead_jones')
    expected_email = metadata.get('expected_email', 'patricia.jones@example.com')
    
    # Required/Forbidden resources
    req_resources = metadata.get('required_resources', [])
    forb_resources = metadata.get('forbidden_resources', [])

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/admin_role_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # ── Criterion 1: Role exists (20 pts) ────────────────────────────────────
    role_found = result.get('role_found', False)
    role_data = result.get('role', {})
    role_name = role_data.get('name', '')
    
    if role_found and role_name == expected_role:
        score += 20
        feedback_parts.append(f"Role '{expected_role}' created (20 pts)")
    elif role_found:
        score += 10
        feedback_parts.append(f"Role found but name mismatch: '{role_name}' (10 pts)")
    else:
        feedback_parts.append("Role 'Customer Service Lead' NOT found")
        # Fail early if role missing? No, might have user. But unlikely to pass.
    
    # ── Criterion 2, 3, 4: Permissions (45 pts total) ────────────────────────
    permissions = role_data.get('allowed_resources', [])
    # Flatten permissions for easier checking
    # Note: permissions is a list of strings
    
    if role_found:
        # Check forbidden (specifically 'all' or 'catalog')
        has_all = 'Magento_Backend::all' in permissions
        has_catalog = 'Magento_Catalog::catalog' in permissions or 'Magento_Catalog::products' in permissions
        has_config = 'Magento_Config::config' in permissions
        
        if has_all:
            feedback_parts.append("FAIL: Role has 'All' resources access (should be Custom)")
        else:
            score += 15
            feedback_parts.append("Role uses Custom resource access (15 pts)")
            
            # Check Denied items
            if not has_catalog and not has_config:
                score += 10
                feedback_parts.append("Role correctly restricts Catalog/System (10 pts)")
            else:
                feedback_parts.append(f"Role incorrectly allows Catalog/Config access")

            # Check Allowed items
            has_sales = 'Magento_Sales::sales' in permissions
            has_customers = 'Magento_Customer::customer' in permissions
            has_dashboard = 'Magento_Backend::dashboard' in permissions
            
            if has_sales:
                score += 10
                feedback_parts.append("Sales access granted (10 pts)")
            else:
                feedback_parts.append("Sales access missing")
                
            if has_customers:
                score += 5
                feedback_parts.append("Customer access granted (5 pts)")
            else:
                feedback_parts.append("Customer access missing")
                
            if has_dashboard:
                score += 5
                feedback_parts.append("Dashboard access granted (5 pts)")
            else:
                feedback_parts.append("Dashboard access missing")

    # ── Criterion 5: User exists (20 pts) ────────────────────────────────────
    user_found = result.get('user_found', False)
    user_data = result.get('user', {})
    
    u_username = user_data.get('username', '')
    u_email = user_data.get('email', '')
    u_active = str(user_data.get('is_active', '0'))
    
    if user_found:
        if u_username == expected_user:
            score += 10
            feedback_parts.append(f"User '{expected_user}' created (10 pts)")
        else:
            score += 5
            feedback_parts.append(f"User found but username mismatch ('{u_username}') (5 pts)")
            
        if u_email == expected_email:
            score += 5
            feedback_parts.append("Email correct (5 pts)")
        else:
            feedback_parts.append(f"Email mismatch ('{u_email}')")
            
        if u_active == '1':
            score += 5
            feedback_parts.append("User is Active (5 pts)")
        else:
            feedback_parts.append("User is Inactive")
    else:
        feedback_parts.append("User 'cs_lead_jones' NOT found")

    # ── Criterion 6: Assignment (10 pts) ─────────────────────────────────────
    assignment_correct = result.get('assignment_correct', False)
    if assignment_correct:
        score += 10
        feedback_parts.append("User assigned to correct role (10 pts)")
    else:
        feedback_parts.append("User NOT assigned to the new role")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }