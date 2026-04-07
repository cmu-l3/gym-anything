#!/usr/bin/env python3
"""
Verifier for Add Fee Schedule Code task in OpenEMR

Verifies that CPT code 99441 was added to the fee schedule with:
- Correct code number (99441)
- Correct code type (CPT4)
- Appropriate description (contains Telephone and/or E/M)
- Correct fee ($45.00 within tolerance)
- Created during task execution (anti-gaming)

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_fee_schedule_code(traj, env_info, task_info):
    """
    Verify that CPT code 99441 was correctly added to the fee schedule.
    
    Scoring (100 points total):
    - Code exists (99441): 30 points
    - Correct code type (CPT4): 20 points
    - Description contains appropriate keywords: 15 points
    - Fee is correct ($45.00 ± $0.50): 25 points
    - Code was created during task (anti-gaming): 10 points
    
    Passing threshold: 75 points (must have code exists + correct type + correct fee)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_code = metadata.get('expected_code', '99441')
    expected_code_type = metadata.get('expected_code_type', 'CPT4')
    expected_fee = metadata.get('expected_fee', 45.00)
    fee_tolerance = metadata.get('fee_tolerance', 0.50)
    expected_keywords = metadata.get('expected_description_keywords', ['Telephone', 'E/M'])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/fee_schedule_code_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "code_exists": False,
            "correct_code_type": False,
            "description_valid": False,
            "fee_correct": False,
            "created_during_task": False
        }
        
        # Extract data from result
        code_found = result.get('code_found', False)
        code_data = result.get('code', {})
        validation = result.get('validation', {})
        initial_total = result.get('initial_total_count', 0)
        current_total = result.get('current_total_count', 0)
        
        logger.info(f"Result data: code_found={code_found}, code={code_data}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Code exists (30 points)
        if code_found:
            code_number = code_data.get('code_number', '')
            if code_number == expected_code:
                score += 30
                subscores["code_exists"] = True
                feedback_parts.append(f"✅ Code {expected_code} found in database")
            else:
                feedback_parts.append(f"❌ Code number mismatch: expected {expected_code}, got {code_number}")
        else:
            feedback_parts.append(f"❌ Code {expected_code} NOT found in database")
            # Early return since nothing else to check
            return {
                "passed": False,
                "score": 0,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": {"result": result}
            }
        
        # CRITERION 2: Correct code type - CPT4 (20 points)
        code_type_key = code_data.get('code_type_key', '')
        code_type_valid = validation.get('code_type_valid', False)
        
        if code_type_valid or code_type_key.upper() == expected_code_type.upper():
            score += 20
            subscores["correct_code_type"] = True
            feedback_parts.append(f"✅ Code type is {expected_code_type}")
        else:
            feedback_parts.append(f"❌ Code type incorrect: expected {expected_code_type}, got {code_type_key}")
        
        # CRITERION 3: Description contains appropriate keywords (15 points)
        code_text = code_data.get('code_text', '')
        has_telephone = validation.get('has_telephone_keyword', False)
        has_em = validation.get('has_em_keyword', False)
        
        # Also do our own check in case export missed something
        code_text_upper = code_text.upper()
        if not has_telephone:
            has_telephone = 'TELEPHONE' in code_text_upper or 'PHONE' in code_text_upper
        if not has_em:
            has_em = any(kw in code_text_upper for kw in ['E/M', 'E&M', 'EVALUATION', 'MANAGEMENT'])
        
        if has_telephone and has_em:
            score += 15
            subscores["description_valid"] = True
            feedback_parts.append(f"✅ Description contains required keywords")
        elif has_telephone or has_em:
            score += 8  # Partial credit
            feedback_parts.append(f"⚠️ Description partially valid (telephone={has_telephone}, e/m={has_em})")
        else:
            feedback_parts.append(f"❌ Description missing keywords: '{code_text}'")
        
        # CRITERION 4: Fee is correct - $45.00 (25 points)
        fee_valid = validation.get('fee_valid', False)
        effective_fee = code_data.get('effective_fee', '')
        
        # Parse fee value
        fee_value = None
        if effective_fee:
            try:
                # Remove currency symbols and whitespace
                fee_str = re.sub(r'[^\d.]', '', str(effective_fee))
                if fee_str:
                    fee_value = float(fee_str)
            except ValueError:
                pass
        
        # Also check the direct fee field
        if fee_value is None or fee_value == 0:
            direct_fee = code_data.get('fee', '')
            if direct_fee and direct_fee != 'NULL':
                try:
                    fee_str = re.sub(r'[^\d.]', '', str(direct_fee))
                    if fee_str:
                        fee_value = float(fee_str)
                except ValueError:
                    pass
        
        if fee_value is not None:
            fee_min = expected_fee - fee_tolerance
            fee_max = expected_fee + fee_tolerance
            
            if fee_min <= fee_value <= fee_max:
                score += 25
                subscores["fee_correct"] = True
                feedback_parts.append(f"✅ Fee is ${fee_value:.2f} (expected ${expected_fee:.2f})")
            elif (expected_fee - 5) <= fee_value <= (expected_fee + 5):
                score += 10  # Partial credit for close
                feedback_parts.append(f"⚠️ Fee ${fee_value:.2f} is close but not exact (expected ${expected_fee:.2f} ± ${fee_tolerance})")
            else:
                feedback_parts.append(f"❌ Fee incorrect: ${fee_value:.2f} (expected ${expected_fee:.2f} ± ${fee_tolerance})")
        else:
            feedback_parts.append(f"❌ Could not parse fee value from '{effective_fee}'")
        
        # CRITERION 5: Code was created during task (10 points) - anti-gaming
        newly_added = validation.get('newly_added', False)
        
        if newly_added:
            score += 10
            subscores["created_during_task"] = True
            feedback_parts.append(f"✅ Code was newly added during task")
        elif current_total > initial_total:
            score += 10
            subscores["created_during_task"] = True
            feedback_parts.append(f"✅ New codes detected (count: {initial_total} → {current_total})")
        else:
            # Don't penalize too harshly if we can't verify timing
            score += 5
            feedback_parts.append(f"⚠️ Could not verify if code was newly created")
        
        # Calculate final result
        # Passing requires: code exists + correct type + correct fee (minimum 75 points)
        key_criteria_met = subscores["code_exists"] and subscores["correct_code_type"] and subscores["fee_correct"]
        passed = score >= 75 and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "code_data": code_data,
                "expected_code": expected_code,
                "expected_fee": expected_fee,
                "actual_fee": fee_value
            }
        }
        
    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Export result file not found - task may not have completed properly",
            "subscores": {
                "code_exists": False,
                "correct_code_type": False,
                "description_valid": False,
                "fee_correct": False,
                "created_during_task": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse export result: {str(e)}",
            "subscores": {
                "code_exists": False,
                "correct_code_type": False,
                "description_valid": False,
                "fee_correct": False,
                "created_during_task": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}",
            "subscores": {
                "code_exists": False,
                "correct_code_type": False,
                "description_valid": False,
                "fee_correct": False,
                "created_during_task": False
            }
        }


if __name__ == "__main__":
    # Test mode - for local debugging
    print("Verifier module loaded successfully")
    print("Function: verify_add_fee_schedule_code")
    print("Expected code: 99441 (CPT4)")
    print("Expected fee: $45.00")