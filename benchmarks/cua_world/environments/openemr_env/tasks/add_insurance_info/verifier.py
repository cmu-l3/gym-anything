#!/usr/bin/env python3
"""
Verifier for Add Insurance Info task in OpenEMR

Robust multi-criteria verification:
1. Insurance record exists for correct patient (25 points)
2. Record was newly created during task (15 points) - anti-gaming
3. Policy number matches expected value (25 points)
4. Group number matches expected value (15 points)
5. Insurance company is Blue Cross Blue Shield (15 points)
6. Subscriber relationship is self (5 points)

Pass threshold: 65 points with insurance record existing and policy number correct
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_insurance_info(traj, env_info, task_info):
    """
    Verify that insurance information was correctly added for the patient.

    Uses copy_from_env to read pre-exported verification data from the container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task_info metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 5)
    expected_policy = metadata.get('expected_policy_number', 'XWP845621379')
    expected_group = metadata.get('expected_group_number', 'GRP7845210')
    expected_company = metadata.get('expected_insurance_company', 'Blue Cross Blue Shield')
    expected_subscriber_rel = metadata.get('expected_subscriber_relationship', 'self')

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_insurance_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found - export_result.sh may have failed"
            }
        except json.JSONDecodeError as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Invalid JSON in result file: {e}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        max_score = 100
        feedback_parts = []
        subscores = {
            "insurance_exists": False,
            "newly_created": False,
            "policy_correct": False,
            "group_correct": False,
            "company_correct": False,
            "subscriber_correct": False
        }

        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_insurance_count', 0)
        current_count = result.get('current_insurance_count', 0)
        ins_found = result.get('insurance_record_found', False)
        new_record = result.get('new_record_created', False)
        insurance = result.get('insurance', {})
        validation = result.get('validation', {})

        logger.info(f"Result data: pid={patient_pid}, initial={initial_count}, current={current_count}, found={ins_found}")
        logger.info(f"Insurance data: {insurance}")

        # Verify we're checking the correct patient
        if patient_pid != expected_pid:
            feedback_parts.append(f"CRITICAL: Wrong patient ID (expected {expected_pid}, got {patient_pid})")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # ================================================================
        # CRITERION 1: Insurance record exists (25 points)
        # ================================================================
        if ins_found:
            score += 25
            subscores["insurance_exists"] = True
            ins_type = insurance.get('type', 'unknown')
            feedback_parts.append(f"Insurance record found (type: {ins_type})")
        else:
            feedback_parts.append("No insurance record found for patient")
            # Check if any records were added to system at all
            if current_count > initial_count:
                feedback_parts.append(f"Note: {current_count - initial_count} record(s) added but not found for this patient")
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # ================================================================
        # CRITERION 2: Record was newly created during task (15 points)
        # Anti-gaming: ensures agent actually did the work
        # ================================================================
        if new_record or current_count > initial_count:
            score += 15
            subscores["newly_created"] = True
            feedback_parts.append(f"Insurance record newly created (count: {initial_count} → {current_count})")
        else:
            feedback_parts.append("Record may have existed before task (anti-gaming check failed)")
            # Don't fail entirely, but this is suspicious

        # ================================================================
        # CRITERION 3: Policy number matches (25 points)
        # This is a key field - must match exactly
        # ================================================================
        policy_number = insurance.get('policy_number', '').strip()
        
        if policy_number == expected_policy:
            score += 25
            subscores["policy_correct"] = True
            feedback_parts.append(f"Policy number correct: {expected_policy}")
        elif policy_number.upper() == expected_policy.upper():
            # Case-insensitive match - partial credit
            score += 20
            subscores["policy_correct"] = True
            feedback_parts.append(f"Policy number correct (case mismatch): {policy_number}")
        elif expected_policy.lower() in policy_number.lower() or policy_number.lower() in expected_policy.lower():
            # Partial match - minimal credit
            score += 10
            feedback_parts.append(f"Policy number partial match: expected '{expected_policy}', got '{policy_number}'")
        else:
            feedback_parts.append(f"Policy number incorrect: expected '{expected_policy}', got '{policy_number}'")

        # ================================================================
        # CRITERION 4: Group number matches (15 points)
        # ================================================================
        group_number = insurance.get('group_number', '').strip()

        if group_number == expected_group:
            score += 15
            subscores["group_correct"] = True
            feedback_parts.append(f"Group number correct: {expected_group}")
        elif group_number.upper() == expected_group.upper():
            score += 12
            subscores["group_correct"] = True
            feedback_parts.append(f"Group number correct (case mismatch): {group_number}")
        elif group_number:
            feedback_parts.append(f"Group number incorrect: expected '{expected_group}', got '{group_number}'")
        else:
            feedback_parts.append("Group number not set")

        # ================================================================
        # CRITERION 5: Insurance company (15 points)
        # Allow variations: Blue Cross, Blue Shield, BCBS
        # ================================================================
        company_name = insurance.get('company_name', '').strip().lower()
        
        # Check if company name contains relevant keywords
        bcbs_keywords = ['blue cross', 'blue shield', 'bcbs', 'bluecross', 'blueshield']
        company_match = any(keyword in company_name for keyword in bcbs_keywords)
        
        if company_match:
            score += 15
            subscores["company_correct"] = True
            feedback_parts.append(f"Insurance company correct: {insurance.get('company_name', 'Unknown')}")
        elif company_name:
            feedback_parts.append(f"Insurance company may not match: got '{insurance.get('company_name', '')}'")
        else:
            # Company might be stored differently (by ID reference)
            provider_id = insurance.get('provider_id', '')
            if provider_id and provider_id not in ['', '0', 'NULL']:
                # Provider ID set but name not retrieved - give partial credit
                score += 8
                feedback_parts.append(f"Insurance company set (provider_id={provider_id})")
            else:
                feedback_parts.append("Insurance company not set")

        # ================================================================
        # CRITERION 6: Subscriber relationship (5 points)
        # ================================================================
        subscriber_rel = insurance.get('subscriber_relationship', '').strip().lower()
        
        # "Self" can be stored various ways: 'self', 'patient', '18' (code), etc.
        self_indicators = ['self', 'patient', '18', 'subscriber']
        if any(ind in subscriber_rel for ind in self_indicators) or subscriber_rel == '':
            # Empty might mean self/default
            if subscriber_rel:
                score += 5
                subscores["subscriber_correct"] = True
                feedback_parts.append(f"Subscriber relationship correct: {subscriber_rel}")
            else:
                score += 3
                feedback_parts.append("Subscriber relationship not explicitly set")
        else:
            feedback_parts.append(f"Subscriber relationship may be incorrect: {subscriber_rel}")

        # ================================================================
        # Final evaluation
        # ================================================================
        # Key criteria: must have insurance record AND policy number correct
        key_criteria_met = subscores["insurance_exists"] and subscores["policy_correct"]
        
        # Pass if score >= 65 AND key criteria met
        passed = (score >= 65) and key_criteria_met

        # Calculate percentage
        score_percentage = int((score / max_score) * 100)

        # Build final feedback
        if passed:
            feedback_parts.insert(0, f"SUCCESS: Insurance added correctly ({score_percentage}%)")
        else:
            if not subscores["insurance_exists"]:
                feedback_parts.insert(0, "FAILED: No insurance record created")
            elif not subscores["policy_correct"]:
                feedback_parts.insert(0, "FAILED: Policy number incorrect")
            else:
                feedback_parts.insert(0, f"FAILED: Score too low ({score_percentage}%)")

        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "initial_count": initial_count,
                "current_count": current_count,
                "policy_entered": insurance.get('policy_number', ''),
                "group_entered": insurance.get('group_number', ''),
                "company_entered": insurance.get('company_name', '')
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        import traceback
        traceback.print_exc()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }