#!/usr/bin/env python3
"""
Verifier for configure_business_details task.

Checks if the business details (Name, Address, Email) were correctly updated
in Manager.io by inspecting the HTML content of the settings/business details page.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_business_details(traj, env_info, task_info):
    """
    Verify that the business details were configured correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Northwind Traders Ltd.")
    expected_email = metadata.get('expected_email', "accounts@northwindtraders.com")
    expected_address_parts = metadata.get('expected_address_parts', [
        "456 Commerce Boulevard",
        "Suite 200",
        "Chicago",
        "60601",
        "United States"
    ])
    initial_name = metadata.get('initial_name', "Northwind Traders")

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

    if not result.get('content_captured', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to capture content from Manager.io. Agent may not have logged in or saved changes."
        }

    final_content = result.get('final_content', '').lower()
    initial_content = result.get('initial_content', '').lower()
    
    score = 0
    feedback_parts = []
    
    # -----------------------------------------------------------------------
    # CRITERION 1: Business Name Updated (30 points)
    # -----------------------------------------------------------------------
    # We check if the NEW name is present
    name_found = expected_name.lower() in final_content
    
    # Anti-gaming: Check if name is DIFFERENT from strictly "Northwind Traders"
    # (Checking if "Northwind Traders Ltd." is present usually implies change, 
    # but we want to ensure the specific "Ltd." part is there).
    
    if name_found:
        score += 30
        feedback_parts.append("Business Name updated correctly")
    elif "northwind traders" in final_content:
        # If they left it as default
        feedback_parts.append("Business Name NOT updated (still default)")
    else:
        feedback_parts.append("Business Name incorrect")

    # -----------------------------------------------------------------------
    # CRITERION 2: Email Configured (20 points)
    # -----------------------------------------------------------------------
    if expected_email.lower() in final_content:
        score += 20
        feedback_parts.append("Email configured correctly")
    else:
        feedback_parts.append(f"Email not found (expected {expected_email})")

    # -----------------------------------------------------------------------
    # CRITERION 3: Address Details (40 points split)
    # -----------------------------------------------------------------------
    address_matches = 0
    total_parts = len(expected_address_parts)
    missed_parts = []
    
    for part in expected_address_parts:
        if part.lower() in final_content:
            address_matches += 1
        else:
            missed_parts.append(part)
    
    # Calculate address score
    if total_parts > 0:
        address_score = int((address_matches / total_parts) * 40)
        score += address_score
    
    if address_matches == total_parts:
        feedback_parts.append("Full Address correct")
    elif address_matches > 0:
        feedback_parts.append(f"Address partially correct ({address_matches}/{total_parts} lines match)")
    else:
        feedback_parts.append("Address details missing")

    # -----------------------------------------------------------------------
    # CRITERION 4: Anti-Gaming / State Change (10 points)
    # -----------------------------------------------------------------------
    # Verify that the state actually changed from initial
    state_changed = (final_content != initial_content) and score > 0
    
    if state_changed:
        score += 10
        feedback_parts.append("State modification verified")
    else:
        feedback_parts.append("No significant state change detected")

    # -----------------------------------------------------------------------
    # Final Result
    # -----------------------------------------------------------------------
    passed = score >= 60 and name_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }