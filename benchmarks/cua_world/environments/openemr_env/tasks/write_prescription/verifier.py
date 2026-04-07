#!/usr/bin/env python3
"""
Verifier for Write Prescription task in OpenEMR

Multi-criteria verification with anti-gaming measures:
1. Prescription exists for correct patient (25 points)
2. Drug is Ciprofloxacin as specified (25 points)
3. Patient ID matches expected (20 points)
4. Quantity is valid/reasonable (15 points)
5. Prescription created during task (15 points)

Pass threshold: 70 points with prescription exists + correct patient
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_write_prescription(traj, env_info, task_info):
    """
    Verify that a prescription for Ciprofloxacin was correctly written.
    
    Uses copy_from_env to read pre-exported results from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 1)
    expected_fname = metadata.get('patient_fname', 'Tressa')
    expected_lname = metadata.get('patient_lname', 'Gusikowski')
    expected_drug = metadata.get('expected_drug', 'Ciprofloxacin')
    min_quantity = metadata.get('min_quantity', 7)
    max_quantity = metadata.get('max_quantity', 30)
    
    # Score weights from metadata (with defaults)
    score_rx_exists = metadata.get('score_prescription_exists', 25)
    score_correct_drug = metadata.get('score_correct_drug', 25)
    score_correct_patient = metadata.get('score_correct_patient', 20)
    score_quantity_valid = metadata.get('score_quantity_valid', 15)
    score_timestamp_valid = metadata.get('score_timestamp_valid', 15)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/write_prescription_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "prescription_exists": False,
            "correct_drug": False,
            "correct_patient": False,
            "quantity_valid": False,
            "newly_created": False
        }
        
        # Extract data from export
        patient_pid = result.get('patient_pid', 0)
        initial_rx_count = result.get('initial_rx_count', 0)
        current_rx_count = result.get('current_rx_count', 0)
        rx_found = result.get('prescription_found', False)
        is_ciprofloxacin = result.get('is_ciprofloxacin', False)
        is_new = result.get('is_new_prescription', False)
        quantity_valid_export = result.get('quantity_valid', False)
        timestamp_valid_export = result.get('timestamp_valid', False)
        prescription = result.get('prescription', {})
        
        logger.info(f"Result: pid={patient_pid}, initial_rx={initial_rx_count}, current_rx={current_rx_count}")
        logger.info(f"Found: {rx_found}, Cipro: {is_ciprofloxacin}, New: {is_new}")
        logger.info(f"Prescription: {prescription}")
        
        # =================================================================
        # CRITERION 1: Prescription exists for patient (25 points)
        # =================================================================
        if rx_found and current_rx_count > initial_rx_count:
            score += score_rx_exists
            subscores["prescription_exists"] = True
            feedback_parts.append(f"Prescription created (count: {initial_rx_count} -> {current_rx_count})")
        elif rx_found:
            # Prescription found but count didn't increase - might be pre-existing
            score += score_rx_exists // 2
            feedback_parts.append("Prescription found but may have existed before task")
        else:
            feedback_parts.append("No prescription found for patient")
            # Early return - nothing else to verify
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {"reason": "No prescription created"}
            }
        
        # =================================================================
        # CRITERION 2: Correct drug (Ciprofloxacin) (25 points)
        # =================================================================
        drug_name = prescription.get('drug', '').lower()
        expected_drug_lower = expected_drug.lower()
        
        if expected_drug_lower in drug_name or 'cipro' in drug_name:
            score += score_correct_drug
            subscores["correct_drug"] = True
            feedback_parts.append(f"Correct drug: {prescription.get('drug', 'N/A')}")
        else:
            feedback_parts.append(f"Wrong drug: expected '{expected_drug}', got '{prescription.get('drug', 'N/A')}'")
        
        # =================================================================
        # CRITERION 3: Correct patient (20 points)
        # =================================================================
        if patient_pid == expected_pid:
            score += score_correct_patient
            subscores["correct_patient"] = True
            feedback_parts.append(f"Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # This is critical - wrong patient is a significant failure
        
        # =================================================================
        # CRITERION 4: Quantity is valid/reasonable (15 points)
        # =================================================================
        quantity_str = prescription.get('quantity', '')
        try:
            # Extract numeric value from quantity
            quantity_match = re.search(r'(\d+)', str(quantity_str))
            if quantity_match:
                quantity = int(quantity_match.group(1))
                if min_quantity <= quantity <= max_quantity:
                    score += score_quantity_valid
                    subscores["quantity_valid"] = True
                    feedback_parts.append(f"Valid quantity: {quantity}")
                elif quantity > 0:
                    # Partial credit for having any quantity
                    score += score_quantity_valid // 2
                    feedback_parts.append(f"Quantity outside expected range: {quantity} (expected {min_quantity}-{max_quantity})")
                else:
                    feedback_parts.append(f"Invalid quantity: {quantity}")
            else:
                feedback_parts.append(f"Could not parse quantity: '{quantity_str}'")
        except (ValueError, TypeError) as e:
            feedback_parts.append(f"Error parsing quantity: {e}")
        
        # =================================================================
        # CRITERION 5: Newly created during task (15 points)
        # Anti-gaming: ensure prescription was created during task execution
        # =================================================================
        if is_new:
            score += score_timestamp_valid
            subscores["newly_created"] = True
            feedback_parts.append("Prescription verified as newly created")
        elif timestamp_valid_export:
            # Timestamp valid but not confirmed as new
            score += score_timestamp_valid // 2
            feedback_parts.append("Timestamp valid but new status uncertain")
        else:
            feedback_parts.append("Could not verify prescription was newly created (potential gaming)")
        
        # =================================================================
        # DETERMINE PASS/FAIL
        # =================================================================
        # Must have: prescription exists + correct patient + correct drug
        key_criteria_met = (
            subscores["prescription_exists"] and
            subscores["correct_patient"] and
            subscores["correct_drug"]
        )
        
        # Pass threshold: 70 points AND key criteria
        passed = score >= 70 and key_criteria_met
        
        # Adjust feedback for overall result
        if passed:
            feedback_parts.insert(0, "SUCCESS: Prescription written correctly")
        elif key_criteria_met:
            feedback_parts.insert(0, f"PARTIAL: Key criteria met but score {score}/100 below threshold")
        else:
            missing = []
            if not subscores["prescription_exists"]:
                missing.append("prescription not created")
            if not subscores["correct_patient"]:
                missing.append("wrong patient")
            if not subscores["correct_drug"]:
                missing.append("wrong drug")
            feedback_parts.insert(0, f"FAILED: Missing key criteria: {', '.join(missing)}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "prescription": prescription,
                "expected_drug": expected_drug,
                "expected_patient_pid": expected_pid,
                "key_criteria_met": key_criteria_met
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {
                "prescription_exists": False,
                "correct_drug": False,
                "correct_patient": False,
                "quantity_valid": False,
                "newly_created": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "prescription_exists": False,
                "correct_drug": False,
                "correct_patient": False,
                "quantity_valid": False,
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
                "prescription_exists": False,
                "correct_drug": False,
                "correct_patient": False,
                "quantity_valid": False,
                "newly_created": False
            }
        }