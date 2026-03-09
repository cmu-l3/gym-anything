#!/usr/bin/env python3
"""
Verifier for Create Customer task in Odoo

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_customer(traj, env_info, task_info):
    """
    Verify that the expected customer was added to Odoo.

    The expected customer details are read from task_info metadata.
    Defaults: Acme Corporation, contact@acme.com, +1-555-0123, New York

    Checks:
    1. Customer with expected name exists in database
    2. Customer email matches expected value
    3. Customer phone matches expected value
    4. Customer city matches expected value
    5. Customer is marked as company (is_company=true)
    6. Customer was created during this session (id > initial count)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Acme Corporation')
    expected_email = metadata.get('expected_email', 'contact@acme.com')
    expected_phone = metadata.get('expected_phone', '+1-555-0123')
    expected_city = metadata.get('expected_city', 'New York')
    expected_is_company = metadata.get('expected_is_company', True)

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
        total_criteria = 6
        feedback_parts = []

        initial_count = result.get('initial_partner_count', 0)
        current_count = result.get('current_partner_count', 0)
        customer_found = result.get('customer_found', False)
        customer = result.get('customer', {})

        logger.info(f"Result data: initial={initial_count}, current={current_count}, found={customer_found}")
        logger.info(f"Customer data: {customer}")

        # Criterion 1: Check if customer exists with expected name
        if customer_found:
            name = customer.get('name', '')

            if name.lower() == expected_name.lower():
                criteria_passed += 1
                feedback_parts.append(f"Customer '{expected_name}' found in database")
            else:
                feedback_parts.append(f"Customer name mismatch: expected '{expected_name}', got '{name}'")
        else:
            feedback_parts.append(f"Customer '{expected_name}' NOT found in database")

            # Check if any new customers were added at all
            if current_count > initial_count:
                new_customers = current_count - initial_count
                feedback_parts.append(f"Note: {new_customers} new partner(s) added, but not with expected name")
            else:
                feedback_parts.append("No new partners were added to the database")

            # Early return since no customer found
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": {
                    "customer_exists": False,
                    "email_correct": False,
                    "phone_correct": False,
                    "city_correct": False,
                    "is_company": False,
                    "newly_added": False
                }
            }

        # Criterion 2: Check email
        email = customer.get('email', '')
        if email and email.lower() == expected_email.lower():
            criteria_passed += 1
            feedback_parts.append(f"Email correct: {expected_email}")
        elif email:
            feedback_parts.append(f"Email incorrect: expected {expected_email}, got {email}")
        else:
            feedback_parts.append(f"Email not set (expected {expected_email})")

        # Criterion 3: Check phone
        phone = customer.get('phone', '')
        # Normalize phone numbers for comparison (remove spaces, dashes)
        phone_normalized = ''.join(c for c in phone if c.isdigit() or c == '+')
        expected_phone_normalized = ''.join(c for c in expected_phone if c.isdigit() or c == '+')
        if phone_normalized == expected_phone_normalized:
            criteria_passed += 1
            feedback_parts.append(f"Phone correct: {expected_phone}")
        elif phone:
            feedback_parts.append(f"Phone incorrect: expected {expected_phone}, got {phone}")
        else:
            feedback_parts.append(f"Phone not set (expected {expected_phone})")

        # Criterion 4: Check city
        city = customer.get('city', '')
        if city and city.lower() == expected_city.lower():
            criteria_passed += 1
            feedback_parts.append(f"City correct: {expected_city}")
        elif city:
            feedback_parts.append(f"City incorrect: expected {expected_city}, got {city}")
        else:
            feedback_parts.append(f"City not set (expected {expected_city})")

        # Criterion 5: Check if marked as company
        is_company = customer.get('is_company', False)
        if is_company == expected_is_company:
            criteria_passed += 1
            feedback_parts.append(f"Company flag correct: {is_company}")
        else:
            feedback_parts.append(f"Company flag incorrect: expected {expected_is_company}, got {is_company}")

        # Criterion 6: Check if customer was newly added (id > initial count)
        id_str = customer.get('id', '0')
        try:
            customer_id = int(id_str) if id_str else 0
            if customer_id > initial_count:
                criteria_passed += 1
                feedback_parts.append(f"Customer newly added with id={customer_id} (initial count was {initial_count})")
            else:
                feedback_parts.append(f"Customer may have existed before task (id={customer_id}, initial_count={initial_count})")
                # Still give partial credit since customer exists with correct details
                criteria_passed += 0.5
        except (ValueError, TypeError):
            feedback_parts.append(f"Could not verify customer ID: {id_str}")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60  # Pass if at least 4 out of 6 criteria met (name + 3 others)

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "customer_exists": customer_found,
                "email_correct": email.lower() == expected_email.lower() if email else False,
                "phone_correct": phone_normalized == expected_phone_normalized,
                "city_correct": city.lower() == expected_city.lower() if city else False,
                "is_company": is_company == expected_is_company,
                "newly_added": criteria_passed >= 6
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
