#!/usr/bin/env python3
"""
Verifier for user_account_setup task.

Scoring (100 points total):
- User fatmata.koroma exists in DHIS2 (30 pts) [MANDATORY]
- Correct first name (Fatmata) and surname (Koroma) (15 pts)
- Correct email address (10 pts)
- At least one user role assigned (20 pts)
- Data capture organisation unit configured (15 pts)
- Account is enabled (not disabled) (10 pts)

Pass threshold: 60 points
Mandatory: User must exist
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_user_account_setup(traj, env_info, task_info):
    """Verify the DHIS2 user account was created with correct configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/user_account_setup_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Get metadata expectations
        metadata = task_info.get('metadata', {})
        expected_username = metadata.get('target_username', 'fatmata.koroma')
        expected_firstname = metadata.get('target_firstname', 'Fatmata')
        expected_surname = metadata.get('target_surname', 'Koroma')
        expected_email = metadata.get('target_email', 'fatmata.koroma@mohsl.gov.sl')

        # Extract user details
        user_found = result.get('user_found', False)
        if isinstance(user_found, str):
            user_found = user_found.lower() == 'true'

        user_details = result.get('user_details', {})
        if isinstance(user_details, str):
            try:
                user_details = json.loads(user_details)
            except:
                user_details = {}

        # Criterion 1: User exists (MANDATORY)
        if not user_found and not user_details.get('user_found', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": f"User '{expected_username}' not found in DHIS2. Agent must create the user account.",
                "subscores": {}
            }

        score += 30
        subscores["user_exists"] = True
        feedback_parts.append(f"User '{expected_username}' found in DHIS2 (+30)")

        # Use user_details for remaining checks
        actual_fname = user_details.get('first_name', '')
        actual_surname = user_details.get('surname', '')
        actual_email = user_details.get('email', '')
        actual_disabled = user_details.get('disabled', True)
        if isinstance(actual_disabled, str):
            actual_disabled = actual_disabled.lower() == 'true'
        role_count = int(user_details.get('role_count', 0))
        capture_ou_count = int(user_details.get('capture_org_unit_count', 0))

        # Criterion 2: Correct name
        fname_match = actual_fname.lower() == expected_firstname.lower()
        surname_match = actual_surname.lower() == expected_surname.lower()

        if fname_match and surname_match:
            score += 15
            subscores["correct_name"] = True
            feedback_parts.append(f"Name correct: {actual_fname} {actual_surname} (+15)")
        else:
            subscores["correct_name"] = False
            feedback_parts.append(f"Name mismatch: got '{actual_fname} {actual_surname}', expected '{expected_firstname} {expected_surname}'")

        # Criterion 3: Correct email
        # Allow partial match (domain may differ)
        if actual_email and (actual_email.lower() == expected_email.lower() or
                             'fatmata' in actual_email.lower() or
                             'koroma' in actual_email.lower()):
            score += 10
            subscores["correct_email"] = True
            feedback_parts.append(f"Email configured: {actual_email} (+10)")
        else:
            subscores["correct_email"] = False
            feedback_parts.append(f"Email missing or incorrect: '{actual_email}'")

        # Criterion 4: At least one role assigned
        if role_count >= 1:
            roles = user_details.get('roles', [])
            score += 20
            subscores["has_role"] = True
            feedback_parts.append(f"{role_count} role(s) assigned: {', '.join(roles[:3])} (+20)")
        else:
            subscores["has_role"] = False
            feedback_parts.append("No user roles assigned — account cannot access DHIS2 functionality")

        # Criterion 5: Data capture org unit configured
        if capture_ou_count >= 1:
            capture_ous = user_details.get('capture_org_units', [])
            score += 15
            subscores["has_capture_ou"] = True
            feedback_parts.append(f"Data capture org units configured ({', '.join(capture_ous[:2])}) (+15)")
        else:
            subscores["has_capture_ou"] = False
            feedback_parts.append("No data capture organisation units assigned — user cannot enter data")

        # Criterion 6: Account is enabled (not disabled)
        if not actual_disabled:
            score += 10
            subscores["account_enabled"] = True
            feedback_parts.append("Account is enabled (+10)")
        else:
            subscores["account_enabled"] = False
            feedback_parts.append("Account is disabled — user cannot log in")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
