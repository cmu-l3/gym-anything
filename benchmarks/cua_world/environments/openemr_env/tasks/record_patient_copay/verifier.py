#!/usr/bin/env python3
"""
Verifier for Record Patient Copay Payment task in OpenEMR

Verifies that a $30 cash copay payment was correctly recorded for patient Jude Sauer (pid=4).

Scoring (100 points total):
- Payment record exists for correct patient: 25 points
- Correct patient (pid=4): 25 points
- Correct amount ($30.00): 20 points
- Correct payment method (cash): 15 points
- Newly created (anti-gaming): 10 points
- Note mentions copay: 5 points

Passing threshold: 70 points with payment_exists and correct_patient
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_amount(amount_str: str) -> Optional[float]:
    """
    Parse amount string to float, handling various formats.
    
    Args:
        amount_str: Amount as string (e.g., "30.00", "$30", "30")
    
    Returns:
        Float amount or None if parsing fails
    """
    if not amount_str:
        return None
    
    try:
        # Remove currency symbols and whitespace
        cleaned = amount_str.replace('$', '').replace(',', '').strip()
        return float(cleaned)
    except (ValueError, TypeError):
        return None


def check_amount_match(actual: float, expected: float, tolerance: float = 0.01) -> bool:
    """
    Check if actual amount matches expected within tolerance.
    
    Args:
        actual: Actual payment amount
        expected: Expected payment amount
        tolerance: Acceptable difference
    
    Returns:
        True if amounts match within tolerance
    """
    if actual is None:
        return False
    return abs(actual - expected) <= tolerance


def check_method_is_cash(method: str) -> bool:
    """
    Check if payment method indicates cash payment.
    
    Args:
        method: Payment method string
    
    Returns:
        True if method indicates cash
    """
    if not method:
        return False
    
    method_lower = method.lower().strip()
    cash_indicators = ['cash', 'money', 'currency', 'cash_payment', 'patient cash']
    
    for indicator in cash_indicators:
        if indicator in method_lower:
            return True
    
    # Also check for common abbreviations
    if method_lower in ['cash', 'ca', 'csh']:
        return True
    
    return False


def check_copay_mentioned(note: str, source: str) -> bool:
    """
    Check if payment description mentions copay.
    
    Args:
        note: Payment note/memo
        source: Payment source field
    
    Returns:
        True if copay is mentioned
    """
    combined = f"{note or ''} {source or ''}".lower()
    
    copay_indicators = [
        'copay', 'co-pay', 'copayment', 'co payment',
        'office visit', 'ov copay', 'patient responsibility'
    ]
    
    for indicator in copay_indicators:
        if indicator in combined:
            return True
    
    return False


def verify_record_copay(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that a copay payment was correctly recorded for the patient.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    The export_result.sh script queries the database and saves results to JSON.
    
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
            "feedback": "Copy function not available for verification"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    expected_amount = metadata.get('expected_amount', 30.00)
    amount_tolerance = metadata.get('amount_tolerance', 0.01)
    
    # Get scoring weights
    weights = metadata.get('scoring_weights', {
        'payment_exists': 25,
        'correct_patient': 25,
        'correct_amount': 20,
        'correct_method': 15,
        'newly_created': 10,
        'copay_noted': 5
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/record_copay_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "payment_exists": False,
            "correct_patient": False,
            "correct_amount": False,
            "correct_method": False,
            "newly_created": False,
            "copay_noted": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        payment_found = result.get('payment_found', False)
        payment = result.get('payment', {})
        validation = result.get('validation', {})
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        
        logger.info(f"Verification data: pid={patient_pid}, found={payment_found}")
        logger.info(f"Payment data: {payment}")
        logger.info(f"Validation: {validation}")
        
        # CRITERION 1: Correct patient (25 points)
        # Must be verifying for the correct patient
        if patient_pid == expected_pid:
            score += weights['correct_patient']
            subscores['correct_patient'] = True
            feedback_parts.append(f"✓ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient - expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Verification error: wrong patient ID ({patient_pid} vs expected {expected_pid})",
                "subscores": subscores,
                "details": result
            }
        
        # CRITERION 2: Payment exists (25 points)
        if payment_found:
            score += weights['payment_exists']
            subscores['payment_exists'] = True
            feedback_parts.append("✓ Payment record found for patient")
        else:
            feedback_parts.append("✗ No payment record found for patient")
            
            # Check if any new payments were added at all
            new_total = validation.get('new_total_payments', 0)
            if new_total > 0:
                feedback_parts.append(f"  (Note: {new_total} new payment(s) added to system, but not for this patient)")
            else:
                feedback_parts.append("  (No new payments were added to the system)")
            
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores,
                "details": result
            }
        
        # CRITERION 3: Newly created (10 points) - Anti-gaming check
        new_payments = validation.get('new_payments_for_patient', 0)
        if new_payments > 0:
            score += weights['newly_created']
            subscores['newly_created'] = True
            feedback_parts.append(f"✓ Payment newly created during task (count +{new_payments})")
        else:
            # Payment exists but wasn't newly created - might be pre-existing
            feedback_parts.append("⚠ Payment may have existed before task started")
            # Partial credit if payment details are correct
        
        # CRITERION 4: Correct amount (20 points)
        payment_amount = parse_amount(payment.get('amount', ''))
        if payment_amount is not None:
            if check_amount_match(payment_amount, expected_amount, amount_tolerance):
                score += weights['correct_amount']
                subscores['correct_amount'] = True
                feedback_parts.append(f"✓ Correct amount: ${payment_amount:.2f}")
            else:
                feedback_parts.append(f"✗ Incorrect amount: ${payment_amount:.2f} (expected ${expected_amount:.2f})")
        else:
            feedback_parts.append(f"✗ Could not parse payment amount: {payment.get('amount', 'N/A')}")
        
        # CRITERION 5: Correct payment method (15 points)
        payment_method = payment.get('method', '')
        is_cash = validation.get('is_cash', False) or check_method_is_cash(payment_method)
        
        if is_cash:
            score += weights['correct_method']
            subscores['correct_method'] = True
            feedback_parts.append(f"✓ Payment method is cash: {payment_method or 'cash'}")
        else:
            if payment_method:
                feedback_parts.append(f"✗ Payment method is not cash: '{payment_method}'")
            else:
                feedback_parts.append("⚠ Payment method not specified")
        
        # CRITERION 6: Copay mentioned in notes (5 points)
        payment_note = payment.get('note', '')
        payment_source = payment.get('source', '')
        mentions_copay = validation.get('mentions_copay', False) or check_copay_mentioned(payment_note, payment_source)
        
        if mentions_copay:
            score += weights['copay_noted']
            subscores['copay_noted'] = True
            feedback_parts.append("✓ Payment note indicates copay")
        else:
            feedback_parts.append("⚠ Payment note does not mention copay")
        
        # Determine pass/fail
        # Must have payment_exists AND correct_patient AND (newly_created OR correct_amount)
        key_criteria_met = (
            subscores['payment_exists'] and 
            subscores['correct_patient'] and
            (subscores['newly_created'] or subscores['correct_amount'])
        )
        
        passed = score >= 70 and key_criteria_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        if passed:
            feedback = f"PASSED ({score}/100): " + feedback
        else:
            feedback = f"FAILED ({score}/100): " + feedback
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "payment_found": payment_found,
                "payment_amount": payment_amount,
                "payment_method": payment_method,
                "is_cash": is_cash,
                "mentions_copay": mentions_copay,
                "new_payments_count": new_payments
            }
        }
        
    except FileNotFoundError:
        logger.error("Result file not found in container")
        return {
            "passed": False,
            "score": 0,
            "feedback": "Verification failed: result file not found. Export may have failed.",
            "subscores": {
                "payment_exists": False,
                "correct_patient": False,
                "correct_amount": False,
                "correct_method": False,
                "newly_created": False,
                "copay_noted": False
            }
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: invalid JSON in result file: {e}",
            "subscores": {
                "payment_exists": False,
                "correct_patient": False,
                "correct_amount": False,
                "correct_method": False,
                "newly_created": False,
                "copay_noted": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "payment_exists": False,
                "correct_patient": False,
                "correct_amount": False,
                "correct_method": False,
                "newly_created": False,
                "copay_noted": False
            }
        }


# For direct testing
if __name__ == "__main__":
    # Mock test
    print("Verifier module loaded successfully")
    print("Function: verify_record_copay")
    print("Expected patient: Jude Sauer (pid=4)")
    print("Expected amount: $30.00")
    print("Expected method: Cash")