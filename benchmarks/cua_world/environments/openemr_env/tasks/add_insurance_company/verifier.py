#!/usr/bin/env python3
"""
Verifier for Add Insurance Company task in OpenEMR

Verifies that a new insurance company was added to the system configuration
with the correct details (Blue Cross Blue Shield of Massachusetts).

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Record exists with correct name: 30 points
- Company name contains expected keywords: 20 points
- Address details correct (city/state): 15 points
- ZIP code correct: 10 points
- Phone number present: 10 points
- Newly created (not pre-existing): 15 points

Pass threshold: 70 points with record_exists AND newly_created
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_phone(phone: str) -> str:
    """Extract digits from phone number for comparison."""
    if not phone:
        return ""
    return re.sub(r'\D', '', phone)


def normalize_state(state: str) -> str:
    """Normalize state to two-letter code."""
    if not state:
        return ""
    state = state.strip().upper()
    state_mapping = {
        "MASSACHUSETTS": "MA",
        "MASS": "MA",
        "MASS.": "MA",
    }
    return state_mapping.get(state, state)


def verify_add_insurance_company(traj, env_info, task_info):
    """
    Verify that the expected insurance company was added to OpenEMR.

    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info including copy_from_env function
        task_info: Task info with metadata containing expected values

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    breakpoint()

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_company_name', 'Blue Cross Blue Shield of Massachusetts')
    expected_city = metadata.get('expected_city', 'Boston')
    expected_state = metadata.get('expected_state', 'MA')
    expected_zip = metadata.get('expected_zip', '02199')
    expected_phone = metadata.get('expected_phone', '(800) 262-2583')
    expected_address = metadata.get('expected_address', '101 Huntington Avenue, Suite 1300')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_insurance_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "record_exists": False,
            "name_correct": False,
            "address_correct": False,
            "zip_correct": False,
            "phone_present": False,
            "newly_created": False
        }

        # Extract data from result
        initial_count = result.get('initial_count', 0)
        current_count = result.get('current_count', 0)
        initial_max_id = result.get('initial_max_id', 0)
        company_found = result.get('company_found', False)
        newly_created = result.get('newly_created', False)
        company = result.get('company', {})

        logger.info(f"Result: initial_count={initial_count}, current_count={current_count}, found={company_found}")
        logger.info(f"Company data: {company}")

        # CRITERION 1: Record exists (30 points)
        if company_found:
            score += 30
            subscores["record_exists"] = True
            feedback_parts.append(f"✅ Insurance company record found (ID: {company.get('id', 'unknown')})")
        else:
            feedback_parts.append("❌ Insurance company record NOT found in database")
            
            # Check if any new records were added at all
            if current_count > initial_count:
                new_count = current_count - initial_count
                feedback_parts.append(f"Note: {new_count} new insurance company record(s) added, but not matching expected name")
            else:
                feedback_parts.append("No new insurance companies were added to the database")
            
            # Early return - nothing more to verify
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Company name correct (20 points)
        company_name = company.get('name', '').lower()
        name_keywords = ['blue cross', 'massachusetts']
        name_match_count = sum(1 for kw in name_keywords if kw in company_name)
        
        if name_match_count == len(name_keywords):
            score += 20
            subscores["name_correct"] = True
            feedback_parts.append(f"✅ Company name correct: contains 'Blue Cross' and 'Massachusetts'")
        elif name_match_count > 0:
            # Partial credit
            partial_score = 10
            score += partial_score
            feedback_parts.append(f"⚠️ Company name partially correct ({partial_score} pts): found {name_match_count}/{len(name_keywords)} keywords")
        else:
            feedback_parts.append(f"❌ Company name incorrect: '{company.get('name', '')}' does not match expected")

        # CRITERION 3: Address details correct - city and state (15 points)
        actual_city = company.get('city', '').strip().lower()
        actual_state = normalize_state(company.get('state', ''))
        expected_state_normalized = normalize_state(expected_state)
        
        city_correct = actual_city == expected_city.lower()
        state_correct = actual_state == expected_state_normalized
        
        if city_correct and state_correct:
            score += 15
            subscores["address_correct"] = True
            feedback_parts.append(f"✅ Address correct: {expected_city}, {expected_state}")
        elif city_correct:
            score += 8
            feedback_parts.append(f"⚠️ City correct ({expected_city}), but state mismatch: expected {expected_state}, got {company.get('state', '')}")
        elif state_correct:
            score += 7
            feedback_parts.append(f"⚠️ State correct ({expected_state}), but city mismatch: expected {expected_city}, got {company.get('city', '')}")
        else:
            feedback_parts.append(f"❌ Address incorrect: expected {expected_city}, {expected_state}, got {company.get('city', '')}, {company.get('state', '')}")

        # CRITERION 4: ZIP code correct (10 points)
        actual_zip = company.get('zip', '').strip()
        # Handle ZIP+4 format by comparing first 5 digits
        actual_zip_5 = actual_zip[:5] if len(actual_zip) >= 5 else actual_zip
        expected_zip_5 = expected_zip[:5]
        
        if actual_zip_5 == expected_zip_5:
            score += 10
            subscores["zip_correct"] = True
            feedback_parts.append(f"✅ ZIP code correct: {expected_zip}")
        elif actual_zip:
            feedback_parts.append(f"❌ ZIP code incorrect: expected {expected_zip}, got {actual_zip}")
        else:
            feedback_parts.append("❌ ZIP code not provided")

        # CRITERION 5: Phone number present (10 points)
        actual_phone = company.get('phone', '').strip()
        if actual_phone:
            score += 10
            subscores["phone_present"] = True
            
            # Check if phone matches expected (bonus feedback, not extra points)
            actual_phone_digits = normalize_phone(actual_phone)
            expected_phone_digits = normalize_phone(expected_phone)
            if actual_phone_digits == expected_phone_digits:
                feedback_parts.append(f"✅ Phone number correct: {expected_phone}")
            else:
                feedback_parts.append(f"✅ Phone number provided: {actual_phone} (expected: {expected_phone})")
        else:
            feedback_parts.append("❌ Phone number not provided")

        # CRITERION 6: Newly created during task (15 points) - ANTI-GAMING
        if newly_created:
            score += 15
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ Record newly created during task (ID > {initial_max_id})")
        else:
            # This could indicate gaming (finding pre-existing record)
            company_id = company.get('id', '0')
            try:
                company_id_int = int(company_id) if company_id else 0
                if company_id_int <= initial_max_id:
                    feedback_parts.append(f"⚠️ Record may have existed before task (ID {company_id} <= initial max {initial_max_id})")
                else:
                    # ID is higher but newly_created was false - might be timing issue
                    score += 10  # Partial credit
                    feedback_parts.append(f"⚠️ Record appears new but verification uncertain")
            except (ValueError, TypeError):
                feedback_parts.append(f"⚠️ Could not verify if record was newly created")

        # Determine pass/fail
        # Must have record_exists AND either newly_created OR significant score
        key_criteria_met = subscores["record_exists"] and (subscores["newly_created"] or score >= 60)
        passed = score >= 70 and key_criteria_met

        # Final feedback
        feedback_parts.insert(0, f"Score: {score}/100")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "company_found": company_found,
                "company_name": company.get('name', ''),
                "company_city": company.get('city', ''),
                "company_state": company.get('state', ''),
                "company_zip": company.get('zip', ''),
                "newly_created": newly_created,
                "initial_count": initial_count,
                "current_count": current_count
            }
        }

    except FileNotFoundError:
        logger.error("Result file not found - export may have failed")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found. Export script may have failed or task was not completed.",
            "subscores": {
                "record_exists": False,
                "name_correct": False,
                "address_correct": False,
                "zip_correct": False,
                "phone_present": False,
                "newly_created": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "record_exists": False,
                "name_correct": False,
                "address_correct": False,
                "zip_correct": False,
                "phone_present": False,
                "newly_created": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "record_exists": False,
                "name_correct": False,
                "address_correct": False,
                "zip_correct": False,
                "phone_present": False,
                "newly_created": False
            }
        }


# For testing
if __name__ == "__main__":
    # Mock test
    print("Add Insurance Company Verifier")
    print("This verifier checks if Blue Cross Blue Shield of Massachusetts was added to OpenEMR")