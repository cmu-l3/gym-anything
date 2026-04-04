#!/usr/bin/env python3
"""Verifier for Create Customer task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_customer(traj, env_info, task_info):
    """
    Verify that the expected customer was created in Magento.

    Checks:
    1. Customer was newly created (count increased during task)
    2. Customer with expected email exists in database
    3. Customer first name matches expected value
    4. Customer last name matches expected value
    5. Customer group matches expected value (General)

    All criteria must be met for the task to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_firstname = metadata.get('expected_firstname', 'Sarah')
    expected_lastname = metadata.get('expected_lastname', 'Johnson')
    expected_email = metadata.get('expected_email', 'sarah.johnson@example.com')
    expected_group = metadata.get('expected_group', 'General')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_customer_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        initial_count = result.get('initial_customer_count', 0)
        current_count = result.get('current_customer_count', 0)
        customer_found = result.get('customer_found', False)
        customer = result.get('customer', {})

        logger.info(f"Result: initial={initial_count}, current={current_count}, found={customer_found}")
        logger.info(f"Customer data: {customer}")

        # Criterion 1: Customer was newly created (count must increase)
        newly_created = current_count > initial_count
        if newly_created:
            criteria_passed += 1
            feedback_parts.append(f"Customer created (count: {initial_count} -> {current_count})")
        else:
            feedback_parts.append(f"No new customer created (count unchanged: {initial_count})")
            # If no new customer was created, fail immediately
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": False,
                    "customer_exists": customer_found,
                    "firstname_correct": False,
                    "lastname_correct": False,
                    "group_correct": False
                }
            }

        # Criterion 2: Customer with expected email exists in database
        if customer_found:
            criteria_passed += 1
            feedback_parts.append("Customer found in database")
        else:
            feedback_parts.append(f"Customer with email '{expected_email}' NOT found in database")
            return {
                "passed": False,
                "score": int((criteria_passed / total_criteria) * 100),
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "newly_created": newly_created,
                    "customer_exists": False,
                    "firstname_correct": False,
                    "lastname_correct": False,
                    "group_correct": False
                }
            }

        # Criterion 3: First name matches (case-insensitive)
        firstname = customer.get('firstname', '')
        firstname_correct = firstname.strip().lower() == expected_firstname.strip().lower()
        if firstname_correct:
            criteria_passed += 1
            feedback_parts.append(f"First name correct: {expected_firstname}")
        else:
            feedback_parts.append(f"First name mismatch: expected '{expected_firstname}', got '{firstname}'")

        # Criterion 4: Last name matches (case-insensitive)
        lastname = customer.get('lastname', '')
        lastname_correct = lastname.strip().lower() == expected_lastname.strip().lower()
        if lastname_correct:
            criteria_passed += 1
            feedback_parts.append(f"Last name correct: {expected_lastname}")
        else:
            feedback_parts.append(f"Last name mismatch: expected '{expected_lastname}', got '{lastname}'")

        # Criterion 5: Customer group matches (case-insensitive)
        group_name = customer.get('group_name', '')
        group_correct = group_name.strip().lower() == expected_group.strip().lower()
        if group_correct:
            criteria_passed += 1
            feedback_parts.append(f"Customer group correct: {expected_group}")
        else:
            feedback_parts.append(f"Customer group mismatch: expected '{expected_group}', got '{group_name}'")

        # Calculate score - all criteria must be met
        score = int((criteria_passed / total_criteria) * 100)
        passed = criteria_passed == total_criteria  # All criteria must pass

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "newly_created": newly_created,
                "customer_exists": customer_found,
                "firstname_correct": firstname_correct,
                "lastname_correct": lastname_correct,
                "group_correct": group_correct
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
