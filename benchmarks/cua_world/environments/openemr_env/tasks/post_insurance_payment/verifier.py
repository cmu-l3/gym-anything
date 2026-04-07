#!/usr/bin/env python3
"""
Verifier for Post Insurance Payment task in OpenEMR

Verifies that an insurance payment was correctly posted to a patient's account.

Scoring (100 points total):
- Payment record exists for correct patient: 30 points
- Payment is newly created (anti-gaming): 20 points
- Payment amount correct (~$85): 20 points
- Adjustment amount recorded (~$15): 15 points
- Reference number present: 10 points
- Payer marked as insurance (not patient): 5 points

Passing threshold: 70 points (must have correct patient + new payment + correct amount)
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_post_insurance_payment(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that an insurance payment was correctly posted.

    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata

    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_payment = float(metadata.get('expected_payment_amount', 85.00))
    expected_adjustment = float(metadata.get('expected_adjustment_amount', 15.00))
    expected_reference = metadata.get('expected_reference', 'EOB2024-7834')
    payment_tolerance = float(metadata.get('payment_tolerance', 1.00))
    adjustment_tolerance = float(metadata.get('adjustment_tolerance', 2.00))

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/insurance_payment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read verification data: {str(e)}"
        }

    score = 0
    feedback_parts = []
    subscores = {
        "correct_patient": False,
        "newly_created": False,
        "payment_amount_correct": False,
        "adjustment_correct": False,
        "reference_present": False,
        "payer_is_insurance": False
    }

    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    initial_ar_count = result.get('initial_ar_count', 0)
    current_ar_count = result.get('current_ar_count', 0)
    payment_found = result.get('new_payment_found', False)
    payment = result.get('payment', {})
    validation = result.get('validation', {})

    logger.info(f"Verification data: pid={patient_pid}, initial_count={initial_ar_count}, "
                f"current_count={current_ar_count}, payment_found={payment_found}")
    logger.info(f"Payment details: {payment}")

    # CRITERION 1: Correct patient (30 points)
    if patient_pid != expected_pid:
        feedback_parts.append(f"CRITICAL: Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    if payment_found:
        score += 30
        subscores["correct_patient"] = True
        feedback_parts.append(f"✓ Payment found for correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"✗ No payment found for patient pid={expected_pid}")
        # Check if any activity was added at all
        if current_ar_count > initial_ar_count:
            feedback_parts.append(f"Note: {current_ar_count - initial_ar_count} new ar_activity record(s) added, but no payment detected")
        else:
            feedback_parts.append("No new payment activity was recorded")
        
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # CRITERION 2: Newly created payment (20 points) - Anti-gaming check
    if current_ar_count > initial_ar_count:
        score += 20
        subscores["newly_created"] = True
        feedback_parts.append(f"✓ New payment record created during task (count: {initial_ar_count} → {current_ar_count})")
    else:
        feedback_parts.append(f"✗ No new payment record detected (count unchanged at {current_ar_count})")
        # This is a potential gaming attempt - claiming existing payment
        # Still continue to check other criteria but flag this

    # CRITERION 3: Payment amount correct (20 points)
    payment_amount = float(payment.get('amount', 0))
    amount_diff = abs(payment_amount - expected_payment)
    
    if amount_diff <= payment_tolerance:
        score += 20
        subscores["payment_amount_correct"] = True
        feedback_parts.append(f"✓ Payment amount correct: ${payment_amount:.2f} (expected ${expected_payment:.2f})")
    elif amount_diff <= payment_tolerance * 2:
        # Partial credit for close amounts
        score += 10
        feedback_parts.append(f"~ Payment amount close: ${payment_amount:.2f} (expected ${expected_payment:.2f}, diff=${amount_diff:.2f})")
    else:
        feedback_parts.append(f"✗ Payment amount incorrect: ${payment_amount:.2f} (expected ${expected_payment:.2f})")

    # CRITERION 4: Adjustment amount recorded (15 points)
    adjustment_amount = float(payment.get('adjustment_amount', 0))
    # Also check separate adjustment record
    adjustment_separate = float(validation.get('adjustment_amount_separate', 0))
    total_adjustment = max(adjustment_amount, adjustment_separate)
    
    adjustment_diff = abs(total_adjustment - expected_adjustment)
    
    if adjustment_diff <= adjustment_tolerance:
        score += 15
        subscores["adjustment_correct"] = True
        feedback_parts.append(f"✓ Adjustment amount correct: ${total_adjustment:.2f} (expected ${expected_adjustment:.2f})")
    elif total_adjustment > 0:
        # Partial credit for recording some adjustment
        score += 7
        feedback_parts.append(f"~ Adjustment recorded but different: ${total_adjustment:.2f} (expected ${expected_adjustment:.2f})")
    else:
        feedback_parts.append(f"✗ No adjustment recorded (expected ${expected_adjustment:.2f})")

    # CRITERION 5: Reference number present (10 points)
    memo = payment.get('memo', '').lower()
    reference_keywords = ['eob', '2024', '7834', expected_reference.lower()]
    reference_found = any(kw in memo for kw in reference_keywords) or validation.get('reference_found', False)
    
    if reference_found:
        score += 10
        subscores["reference_present"] = True
        feedback_parts.append(f"✓ Reference/memo contains EOB information")
    elif memo:
        # Partial credit for having some memo
        score += 5
        feedback_parts.append(f"~ Memo present but no EOB reference found: '{payment.get('memo', '')[:50]}'")
    else:
        feedback_parts.append(f"✗ No reference number in payment memo (expected '{expected_reference}')")

    # CRITERION 6: Payer marked as insurance (5 points)
    payer_type = payment.get('payer_type', '')
    payer_is_insurance = validation.get('payer_is_insurance', False)
    
    # payer_type: 0=patient, 1=primary insurance, 2=secondary, 3=tertiary
    if payer_is_insurance or payer_type in ['1', '2', '3', 1, 2, 3]:
        score += 5
        subscores["payer_is_insurance"] = True
        feedback_parts.append(f"✓ Payment marked as insurance (payer_type={payer_type})")
    elif payer_type == '0' or payer_type == 0:
        feedback_parts.append(f"✗ Payment marked as patient payment, should be insurance")
    else:
        # Unknown payer type - give partial credit
        score += 2
        feedback_parts.append(f"~ Payer type unclear: '{payer_type}'")

    # Determine pass/fail
    # Must have: correct patient (30) + newly created (20) + correct amount (20) = 70 minimum
    key_criteria_met = (
        subscores["correct_patient"] and 
        subscores["newly_created"] and 
        subscores["payment_amount_correct"]
    )
    
    passed = score >= 70 and key_criteria_met

    # Build final feedback
    feedback_summary = f"Score: {score}/100"
    if passed:
        feedback_summary = f"✓ PASSED - {feedback_summary}"
    else:
        feedback_summary = f"✗ FAILED - {feedback_summary}"
        if not subscores["newly_created"]:
            feedback_summary += " (no new payment created)"
        elif not subscores["payment_amount_correct"]:
            feedback_summary += " (payment amount incorrect)"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_summary + " | " + " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "patient_pid": patient_pid,
            "payment_amount": payment_amount,
            "adjustment_amount": total_adjustment,
            "expected_payment": expected_payment,
            "expected_adjustment": expected_adjustment,
            "reference_found": reference_found,
            "payer_type": payer_type
        }
    }


# For standalone testing
if __name__ == "__main__":
    # Test with mock data
    test_result = {
        "patient_pid": 3,
        "initial_ar_count": 0,
        "current_ar_count": 1,
        "new_payment_found": True,
        "payment": {
            "sequence_no": "1",
            "encounter": "5",
            "payer_type": "1",
            "amount": 85.00,
            "adjustment_amount": 15.00,
            "memo": "EOB2024-7834 Blue Cross",
            "post_time": "2024-01-15 10:30:00"
        },
        "validation": {
            "reference_found": True,
            "payer_is_insurance": True,
            "adjustment_found": True,
            "adjustment_amount_separate": 0
        }
    }
    
    # Mock env_info and task_info
    import tempfile
    import json
    
    # Write test result to temp file
    temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False)
    json.dump(test_result, temp_file)
    temp_file.close()
    
    def mock_copy(src, dst):
        import shutil
        shutil.copy(temp_file.name, dst)
    
    mock_env_info = {'copy_from_env': mock_copy}
    mock_task_info = {
        'metadata': {
            'patient_pid': 3,
            'expected_payment_amount': 85.00,
            'expected_adjustment_amount': 15.00,
            'expected_reference': 'EOB2024-7834'
        }
    }
    
    result = verify_post_insurance_payment({}, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))
    
    # Cleanup
    os.unlink(temp_file.name)