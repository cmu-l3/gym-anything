#!/usr/bin/env python3
"""
Verifier for Manage Credentials task in Jenkins

Checks if a credential was added to the Jenkins global credentials store.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_manage_credentials(traj, env_info, task_info):
    """
    Verify that a credential was added to Jenkins.

    Checks:
    1. Credential exists in the global store
    2. Credential has correct ID
    3. Credential is the correct type (UsernamePasswordCredentials)
    4. Credential has correct username
    5. Credential has correct description
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_id = metadata.get('expected_credential_id', 'deploy-credentials')
    expected_username = metadata.get('expected_username', 'deploy-user')
    expected_description = metadata.get('expected_description', 'Deployment server credentials')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/manage_credentials_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        cred_found = result.get('credential_found', False)
        cred = result.get('credential', {})

        logger.info(f"Result data: found={cred_found}, credential={cred}")

        # Criterion 1: Credential exists
        if cred_found:
            criteria_passed += 1
            feedback_parts.append("Credential found in Jenkins store")
        else:
            feedback_parts.append("No matching credential found in Jenkins store")
            initial = result.get('initial_credential_count', 0)
            current = result.get('current_credential_count', 0)
            if current > initial:
                feedback_parts.append(f"Note: {current - initial} new credential(s) added but ID/description doesn't match")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "credential_exists": False,
                    "correct_id": False,
                    "correct_type": False,
                    "correct_username": False,
                    "correct_description": False
                }
            }

        # Criterion 2: Correct ID
        cred_id = cred.get('id', '')
        if cred_id == expected_id:
            criteria_passed += 1
            feedback_parts.append(f"Credential ID correct: '{expected_id}'")
        elif cred_id and 'deploy' in cred_id.lower():
            criteria_passed += 0.5
            feedback_parts.append(f"Credential ID similar: '{cred_id}' (expected '{expected_id}')")
        else:
            feedback_parts.append(f"Credential ID mismatch: got '{cred_id}' (expected '{expected_id}')")

        # Criterion 3: Correct type (UsernamePasswordCredentials)
        cred_type = cred.get('type', '')
        if 'UsernamePassword' in cred_type or 'usernamePassword' in cred_type.lower():
            criteria_passed += 1
            feedback_parts.append("Credential type correct: Username with password")
        elif cred_type:
            feedback_parts.append(f"Credential type incorrect: '{cred_type}' (expected Username with password)")
        else:
            feedback_parts.append("Credential type not detected")

        # Criterion 4: Correct username
        cred_username = cred.get('username', '')
        if cred_username == expected_username:
            criteria_passed += 1
            feedback_parts.append(f"Username correct: '{expected_username}'")
        elif cred_username and 'deploy' in cred_username.lower():
            criteria_passed += 0.5
            feedback_parts.append(f"Username similar: '{cred_username}' (expected '{expected_username}')")
        elif cred_username:
            feedback_parts.append(f"Username incorrect: '{cred_username}' (expected '{expected_username}')")
        else:
            feedback_parts.append("Username not detected (API may not expose it)")
            # Give partial credit - Jenkins API sometimes hides username
            criteria_passed += 0.25

        # Criterion 5: Correct description
        cred_desc = cred.get('description', '')
        if cred_desc.lower() == expected_description.lower():
            criteria_passed += 1
            feedback_parts.append(f"Description correct: '{expected_description}'")
        elif cred_desc and 'deploy' in cred_desc.lower():
            criteria_passed += 0.75
            feedback_parts.append(f"Description similar: '{cred_desc}' (expected '{expected_description}')")
        elif cred_desc:
            criteria_passed += 0.25
            feedback_parts.append(f"Description set but different: '{cred_desc}' (expected '{expected_description}')")
        else:
            feedback_parts.append("Description not set")

        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "credential_exists": cred_found,
                "correct_id": cred_id == expected_id,
                "correct_type": 'UsernamePassword' in cred_type,
                "correct_username": cred_username == expected_username,
                "correct_description": cred_desc.lower() == expected_description.lower() if cred_desc else False
            }
        }

    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
