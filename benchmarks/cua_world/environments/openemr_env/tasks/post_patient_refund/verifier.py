#!/usr/bin/env python3
"""
Verifier for Post Patient Refund task in OpenEMR

Verifies that a refund was correctly posted to a patient's account.
Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- Correct patient (15 pts): Refund posted to Marcus Cartwright
- Navigation to billing (15 pts): New billing records created
- Refund amount correct (25 pts): Amount is -$45.00 (±$1.00 tolerance)
- Documentation present (20 pts): Memo contains refund-related keywords
- Transaction saved (15 pts): Record exists in database
- Timestamp valid (10 pts): Transaction created after task start

Passing threshold: 70 points with transaction_saved criterion met
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_post_refund(traj, env_info, task_info):
    """
    Verify that patient refund was posted correctly.

    Args:
        traj: Trajectory data with frames, steps, episode_dir
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
    expected_fname = metadata.get('patient_fname', 'Marcus')
    expected_lname = metadata.get('patient_lname', 'Cartwright')
    expected_amount = metadata.get('refund_amount', 45.00)
    amount_tolerance = metadata.get('refund_amount_tolerance', 1.00)
    expected_keywords = metadata.get('expected_keywords', 
                                     ['overpay', 'refund', 'credit', 'balance', 'insurance'])

    score = 0
    feedback_parts = []
    subscores = {
        "patient_correct": False,
        "navigation_billing": False,
        "refund_amount_correct": False,
        "documentation_present": False,
        "transaction_saved": False,
        "timestamp_valid": False
    }

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/post_refund_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not read verification data: {str(e)}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        # Extract data from result
        patient = result.get('patient', {})
        counts = result.get('counts', {})
        refund = result.get('refund', {})
        validation = result.get('validation', {})
        task_start = result.get('task_start_timestamp', 0)

        patient_pid = patient.get('pid', 0)
        patient_fname = patient.get('fname', '')
        patient_lname = patient.get('lname', '')

        refund_found = refund.get('found', False)
        refund_amount_str = refund.get('amount', '0')
        refund_memo = refund.get('memo', '')
        refund_source = refund.get('source', '')
        refund_timestamp = refund.get('timestamp', 0)
        new_records = counts.get('new_records_created', False)

        logger.info(f"Verification data: patient={patient_fname} {patient_lname} (pid={patient_pid})")
        logger.info(f"Refund found: {refund_found}, amount: {refund_amount_str}")
        logger.info(f"Memo: {refund_memo}, Source: {refund_source}")

        # CRITERION 1: Correct patient (15 points)
        if patient_fname.lower() == expected_fname.lower() and \
           patient_lname.lower() == expected_lname.lower():
            if refund_found or new_records:
                score += 15
                subscores["patient_correct"] = True
                feedback_parts.append(f"✅ Correct patient: {expected_fname} {expected_lname}")
            else:
                feedback_parts.append(f"⚠️ Correct patient identified but no refund found")
        else:
            feedback_parts.append(f"❌ Patient mismatch: expected {expected_fname} {expected_lname}")

        # Check if any refund/transaction was found
        if not refund_found and not new_records:
            feedback_parts.append("❌ No refund transaction found in database")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }

        # CRITERION 2: Navigation to billing (15 points)
        # Evidence: new records were created in billing tables
        initial_ar = counts.get('initial_ar_count', 0)
        current_ar = counts.get('current_ar_count', 0)
        initial_pay = counts.get('initial_pay_count', 0)
        current_pay = counts.get('current_pay_count', 0)

        if new_records or current_ar > initial_ar or current_pay > initial_pay:
            score += 15
            subscores["navigation_billing"] = True
            feedback_parts.append("✅ New billing records created (navigated to billing)")
        else:
            feedback_parts.append("⚠️ No new billing records detected")

        # CRITERION 3: Refund amount correct (25 points)
        if refund_found:
            try:
                # Parse the refund amount (may have negative sign)
                refund_amount = float(refund_amount_str.replace('$', '').strip())
                # Check if it's negative and within tolerance of expected amount
                abs_amount = abs(refund_amount)
                
                if (expected_amount - amount_tolerance) <= abs_amount <= (expected_amount + amount_tolerance):
                    if refund_amount < 0:
                        score += 25
                        subscores["refund_amount_correct"] = True
                        feedback_parts.append(f"✅ Refund amount correct: ${refund_amount:.2f}")
                    else:
                        # Amount is positive but correct value - partial credit
                        score += 15
                        feedback_parts.append(f"⚠️ Amount ${refund_amount:.2f} should be negative for refund")
                else:
                    feedback_parts.append(f"❌ Refund amount incorrect: ${refund_amount:.2f} (expected ~-${expected_amount:.2f})")
            except (ValueError, TypeError) as e:
                logger.warning(f"Could not parse refund amount '{refund_amount_str}': {e}")
                feedback_parts.append(f"⚠️ Could not verify refund amount: {refund_amount_str}")

        # CRITERION 4: Documentation present (20 points)
        combined_text = f"{refund_memo} {refund_source}".lower()
        keywords_found = [kw for kw in expected_keywords if kw in combined_text]

        if keywords_found:
            score += 20
            subscores["documentation_present"] = True
            feedback_parts.append(f"✅ Documentation contains keywords: {', '.join(keywords_found)}")
        elif refund_memo or refund_source:
            # Some documentation exists but without expected keywords
            score += 10
            feedback_parts.append(f"⚠️ Documentation exists but missing expected keywords")
        else:
            feedback_parts.append("❌ No refund reason documented")

        # CRITERION 5: Transaction saved (15 points)
        if refund_found:
            score += 15
            subscores["transaction_saved"] = True
            feedback_parts.append("✅ Refund transaction saved to database")
        elif new_records:
            score += 10
            feedback_parts.append("⚠️ New billing record created (may not be refund)")

        # CRITERION 6: Timestamp valid (10 points) - anti-gaming check
        if refund_timestamp and task_start:
            if refund_timestamp > task_start:
                score += 10
                subscores["timestamp_valid"] = True
                feedback_parts.append("✅ Transaction created during task execution")
            else:
                feedback_parts.append("⚠️ Transaction may predate task start")
        elif validation.get('timestamp_valid', False):
            score += 10
            subscores["timestamp_valid"] = True
            feedback_parts.append("✅ Timestamp validation passed")
        else:
            feedback_parts.append("⚠️ Could not verify transaction timestamp")

        # Determine if passed
        # Must have transaction saved and score >= 70
        key_criteria_met = subscores["transaction_saved"] or new_records
        passed = score >= 70 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "refund_amount": refund_amount_str,
                "refund_found": refund_found,
                "new_records_created": new_records
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        import traceback
        traceback.print_exc()
        return {
            "passed": False,
            "score": score,
            "feedback": f"Verification error: {str(e)}",
            "subscores": subscores
        }


def verify_via_vlm(traj, env_info, task_info):
    """
    Optional VLM-based verification using trajectory frames.
    
    This provides secondary verification by analyzing screenshots
    to confirm the agent navigated to billing and entered refund data.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}

    # Import trajectory frame sampling
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    except ImportError:
        return {"success": False, "error": "VLM utilities not available"}

    # Sample frames from trajectory to verify workflow
    frames = sample_trajectory_frames(traj, n=5)
    final = get_final_screenshot(traj)

    if not frames and not final:
        return {"success": False, "error": "No screenshots available"}

    # Combine frames for analysis
    all_frames = frames + ([final] if final else [])

    vlm_prompt = """You are verifying if a billing task was completed in OpenEMR (Electronic Health Records).

TASK: Post a $45.00 refund for patient Marcus Cartwright.

Analyze these screenshots and determine:
1. Did the agent log into OpenEMR?
2. Did the agent search for or access a patient record?
3. Did the agent navigate to a billing/fees/payments section?
4. Did the agent enter payment/refund information?
5. Is there evidence of a negative amount or refund being posted?

Respond in JSON format:
{
    "logged_in": true/false,
    "patient_accessed": true/false,
    "billing_section_visited": true/false,
    "payment_entered": true/false,
    "refund_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of workflow observed"
}
"""

    try:
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        return vlm_result
    except Exception as e:
        return {"success": False, "error": str(e)}


# Entry point for standalone testing
if __name__ == "__main__":
    # Test with mock data
    print("Post Patient Refund Verifier - Standalone Test")
    print("=" * 50)
    
    # Create mock result for testing
    mock_result = {
        "task_start_timestamp": 1700000000,
        "task_end_timestamp": 1700000300,
        "patient": {
            "pid": 10,
            "fname": "Marcus",
            "lname": "Cartwright"
        },
        "counts": {
            "initial_ar_count": 0,
            "current_ar_count": 1,
            "initial_pay_count": 0,
            "current_pay_count": 1,
            "new_records_created": True
        },
        "refund": {
            "found": True,
            "amount": "-45.00",
            "memo": "Insurance overpayment - credit balance refund",
            "source": "Check",
            "timestamp": 1700000250,
            "from_ar_activity": True,
            "from_payments": False
        },
        "validation": {
            "amount_correct": True,
            "documentation_valid": True,
            "timestamp_valid": True
        },
        "screenshot_exists": True
    }
    
    print("Mock result:", json.dumps(mock_result, indent=2))
    print("\nNote: Run with actual environment to perform full verification")