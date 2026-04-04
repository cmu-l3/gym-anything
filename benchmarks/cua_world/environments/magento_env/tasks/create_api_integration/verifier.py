#!/usr/bin/env python3
"""Verifier for Create API Integration task in Magento.

Task: Create 'FastTrack_Logistics' integration, custom resources (Orders View, Inventory), and Activate it.

Criteria:
1. Integration exists with correct name (20 pts)
2. Email matches expected (10 pts)
3. Status is Active (1) (means 'Activate' -> 'Allow' was clicked) (30 pts)
4. OAuth tokens generated (secondary proof of activation) (10 pts)
5. Resource permissions are restricted (Custom) and contain required nodes (30 pts)

Pass threshold: 70 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_api_integration(traj, env_info, task_info):
    """
    Verify API integration creation and activation.
    """
    copy_fn = env_info.get('copy_from_env')
    if not copy_fn:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_fn("/tmp/api_integration_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    logger.info(f"Result: {result}")

    score = 0
    feedback_parts = []
    
    # Expected values
    EXP_NAME = "FastTrack_Logistics"
    EXP_EMAIL = "api@fasttrack.com"
    
    # 1. Integration Exists (20 pts)
    int_found = result.get('integration_found', False)
    name = result.get('name', '')
    
    if int_found and EXP_NAME.lower() in name.lower():
        score += 20
        feedback_parts.append("Integration 'FastTrack_Logistics' created (20 pts)")
    else:
        feedback_parts.append("Integration 'FastTrack_Logistics' NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Email Correct (10 pts)
    email = result.get('email', '')
    if EXP_EMAIL.lower() == email.lower():
        score += 10
        feedback_parts.append("Email correct (10 pts)")
    else:
        feedback_parts.append(f"Email mismatch: got '{email}'")

    # 3. Status is Active (30 pts)
    # Status 1 = Active, 0 = Inactive
    status = str(result.get('status', '0')).strip()
    if status == '1':
        score += 30
        feedback_parts.append("Status is Active (Activation completed) (30 pts)")
    else:
        feedback_parts.append("Status is Inactive (Did you click Activate -> Allow?) (0 pts)")

    # 4. OAuth Tokens Exist (10 pts)
    token_count = int(result.get('token_count', 0))
    if token_count > 0:
        score += 10
        feedback_parts.append("OAuth tokens generated (10 pts)")
    else:
        feedback_parts.append("No OAuth tokens found (Activation incomplete)")

    # 5. Resource Permissions (30 pts)
    # We check if the resource list contains specific required nodes.
    # Note: If 'all' is present, it means they didn't select Custom, which is wrong.
    resources_str = result.get('resources', '')
    resources = [r.strip() for r in resources_str.split(',') if r.strip()]
    
    # Check for 'Magento_Backend::all' which implies full access (incorrect)
    has_full_access = any('Magento_Backend::all' in r for r in resources)
    
    # Required substrings (Magento version agnostic)
    # Sales/Order View
    has_sales = any('Magento_Sales::view' in r or 'Magento_Sales::actions_view' in r for r in resources)
    # Inventory/Products
    has_inventory = any('Magento_CatalogInventory::inventory' in r or 'Magento_CatalogInventory::products' in r for r in resources)

    if has_full_access:
        feedback_parts.append("Incorrect Permissions: Full Resource Access granted (Should be Custom) (0 pts)")
    elif has_sales and has_inventory:
        score += 30
        feedback_parts.append("Custom Resource Permissions correct (Sales+Inventory) (30 pts)")
    elif has_sales or has_inventory:
        score += 15
        feedback_parts.append("Partial Resource Permissions (Missing either Sales or Inventory) (15 pts)")
    else:
        feedback_parts.append("Incorrect Resource Permissions (0 pts)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }