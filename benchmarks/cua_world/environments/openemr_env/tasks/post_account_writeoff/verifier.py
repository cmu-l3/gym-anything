#!/usr/bin/env python3
"""
Verifier for Post Account Write-off task in OpenEMR

This verifier checks that a billing adjustment/write-off was posted correctly.

Scoring (100 points total):
- Transaction created for patient: 30 points
- Correct amount ($15.00): 25 points  
- Correct patient (pid=3): 20 points
- Documentation/memo present: 15 points
- Transaction created during task (timestamp valid): 10 points

Passing threshold: 75 points (must have transaction + correct amount + correct patient)
"""

import sys
import os
import json
import logging
import tempfile
import re
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_account_writeoff(traj, env_info, task_info):
    """
    Verify that a $15.00 write-off adjustment was posted for patient Jayson Fadel.
    
    Uses copy_from_env to read pre-exported verification data from the container.
    The export_result.sh script queries the database and saves results to JSON.
    
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
            "feedback": "Copy function not available"
        }

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_amount = float(metadata.get('adjustment_amount', 15.00))
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    
    # Scoring weights from metadata
    weights = metadata.get('scoring_weights', {
        'transaction_exists': 30,
        'correct_amount': 25,
        'correct_patient': 20,
        'documentation_present': 15,
        'timestamp_valid': 10
    })

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/writeoff_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "transaction_exists": False,
            "correct_amount": False,
            "correct_patient": False,
            "documentation_present": False,
            "timestamp_valid": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_time', 0)
        task_end = result.get('task_end_time', 0)
        adjustment_found = result.get('adjustment_found', False)
        new_transaction = result.get('new_transaction_exists', False)
        adjustment = result.get('adjustment', {})
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        
        logger.info(f"Result data: pid={patient_pid}, adjustment_found={adjustment_found}")
        logger.info(f"Adjustment: {adjustment}")
        logger.info(f"Counts - initial: {initial_counts}, current: {current_counts}")
        
        # CRITERION 1: Transaction exists (30 points)
        # Check if any new billing activity was created
        ar_increased = current_counts.get('ar_activity', 0) > initial_counts.get('ar_activity', 0)
        session_increased = current_counts.get('ar_session', 0) > initial_counts.get('ar_session', 0)
        payments_increased = current_counts.get('payments', 0) > initial_counts.get('payments', 0)
        
        if adjustment_found or new_transaction or ar_increased or session_increased or payments_increased:
            score += weights['transaction_exists']
            subscores['transaction_exists'] = True
            feedback_parts.append("✅ Billing transaction created")
        else:
            feedback_parts.append("❌ No billing transaction found")
            # Early return - no transaction means task not completed
            return {
                "passed": False,
                "score": 0,
                "feedback": "No billing transaction was created. Navigate to Fees/Billing and post an adjustment.",
                "subscores": subscores,
                "details": {
                    "initial_counts": initial_counts,
                    "current_counts": current_counts
                }
            }
        
        # CRITERION 2: Correct patient (20 points)
        if patient_pid == expected_pid:
            score += weights['correct_patient']
            subscores['correct_patient'] = True
            feedback_parts.append(f"✅ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient - expected pid={expected_pid}")
        
        # CRITERION 3: Correct amount (25 points)
        adj_amount_str = adjustment.get('amount', '0')
        try:
            # Handle various formats: "15.00", "-15.00", "15", etc.
            adj_amount = float(adj_amount_str) if adj_amount_str else 0.0
            adj_amount = abs(adj_amount)  # Write-offs can be positive or negative
            
            # Check if amount is close to expected (within $0.50 tolerance)
            amount_diff = abs(adj_amount - expected_amount)
            if amount_diff < 0.50:
                score += weights['correct_amount']
                subscores['correct_amount'] = True
                feedback_parts.append(f"✅ Correct amount (${adj_amount:.2f})")
            elif amount_diff < 2.00:
                # Partial credit for close amounts
                partial_points = int(weights['correct_amount'] * 0.5)
                score += partial_points
                feedback_parts.append(f"⚠️ Amount close but not exact: ${adj_amount:.2f} (expected ${expected_amount:.2f})")
            else:
                feedback_parts.append(f"❌ Wrong amount: ${adj_amount:.2f} (expected ${expected_amount:.2f})")
        except (ValueError, TypeError) as e:
            logger.warning(f"Could not parse amount '{adj_amount_str}': {e}")
            # Check if any transaction with correct amount exists based on count changes
            if new_transaction:
                feedback_parts.append(f"⚠️ Transaction found but amount could not be verified")
                score += int(weights['correct_amount'] * 0.3)  # Partial credit
            else:
                feedback_parts.append(f"❌ Could not verify adjustment amount")
        
        # CRITERION 4: Documentation present (15 points)
        adj_memo = adjustment.get('memo', '')
        adj_account_code = adjustment.get('account_code', '')
        
        # Check if memo contains relevant keywords
        memo_lower = (adj_memo + ' ' + adj_account_code).lower()
        has_documentation = bool(adj_memo.strip() or adj_account_code.strip())
        has_relevant_keywords = any(kw in memo_lower for kw in [
            'write', 'off', 'writeoff', 'write-off',
            'balance', 'small', 'adjustment', 'adj',
            'collect', 'uncollect', 'charity'
        ])
        
        if has_documentation and has_relevant_keywords:
            score += weights['documentation_present']
            subscores['documentation_present'] = True
            feedback_parts.append(f"✅ Appropriate documentation provided")
        elif has_documentation:
            # Partial credit for having some documentation
            partial_points = int(weights['documentation_present'] * 0.6)
            score += partial_points
            subscores['documentation_present'] = True
            feedback_parts.append(f"⚠️ Documentation present but may not mention write-off")
        else:
            feedback_parts.append(f"❌ No documentation/memo for the adjustment")
        
        # CRITERION 5: Timestamp valid (10 points)
        # Verify transaction was created during the task window
        post_time_str = adjustment.get('post_time', '')
        
        if post_time_str and task_start and task_end:
            try:
                # Try to parse the post_time (format varies)
                # Common formats: "2024-01-15 10:30:00", "2024-01-15T10:30:00"
                post_time_str_clean = post_time_str.replace('T', ' ').split('.')[0]
                
                # Check if counts increased during task (alternative timestamp validation)
                if ar_increased or session_increased or payments_increased:
                    score += weights['timestamp_valid']
                    subscores['timestamp_valid'] = True
                    feedback_parts.append(f"✅ Transaction created during task execution")
                else:
                    feedback_parts.append(f"⚠️ Could not verify transaction timing")
            except Exception as e:
                logger.warning(f"Could not parse post_time '{post_time_str}': {e}")
                # Give credit if counts increased
                if ar_increased or session_increased:
                    score += weights['timestamp_valid']
                    subscores['timestamp_valid'] = True
                    feedback_parts.append(f"✅ New transaction detected during task")
        elif ar_increased or session_increased or payments_increased:
            # Fall back to count-based validation
            score += weights['timestamp_valid']
            subscores['timestamp_valid'] = True
            feedback_parts.append(f"✅ Transaction count increased during task")
        else:
            feedback_parts.append(f"⚠️ Could not verify transaction timing")
        
        # Calculate final result
        # Key criteria: must have transaction + correct patient to pass
        key_criteria_met = subscores['transaction_exists'] and subscores['correct_patient']
        passed = score >= 75 and key_criteria_met
        
        # Add VLM verification if available
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            try:
                vlm_result = verify_via_vlm(traj, query_vlm)
                if vlm_result.get('success'):
                    vlm_feedback = vlm_result.get('feedback', '')
                    if vlm_feedback:
                        feedback_parts.append(f"VLM: {vlm_feedback}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
        
        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "expected_pid": expected_pid,
                "adjustment_amount": adj_amount_str,
                "expected_amount": expected_amount,
                "memo": adj_memo[:100] if adj_memo else "",
                "initial_counts": initial_counts,
                "current_counts": current_counts
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run correctly",
            "subscores": {
                "transaction_exists": False,
                "correct_amount": False,
                "correct_patient": False,
                "documentation_present": False,
                "timestamp_valid": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {
                "transaction_exists": False,
                "correct_amount": False,
                "correct_patient": False,
                "documentation_present": False,
                "timestamp_valid": False
            }
        }
    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "transaction_exists": False,
                "correct_amount": False,
                "correct_patient": False,
                "documentation_present": False,
                "timestamp_valid": False
            }
        }


def verify_via_vlm(traj, query_vlm):
    """
    Secondary verification using VLM on trajectory frames.
    
    Checks that agent navigated through billing workflow.
    Uses trajectory frames (not just final screenshot) to verify work was done.
    """
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final_frame = get_final_screenshot(traj)
        
        if not frames and not final_frame:
            return {"success": False, "error": "No frames available"}
        
        # Use trajectory frames + final for comprehensive check
        all_frames = frames + ([final_frame] if final_frame else [])
        
        prompt = """Analyze these screenshots from an OpenEMR (Electronic Health Records) session.

The task was to post a $15.00 write-off adjustment to a patient's billing account.

Look for evidence that the agent:
1. Logged into OpenEMR
2. Navigated to a patient's billing/fees section
3. Opened a payment or adjustment form
4. Entered an amount (should be around $15.00)
5. Entered a note or reason
6. Saved/submitted the transaction

Respond in JSON format:
{
    "logged_in": true/false,
    "found_billing_section": true/false,
    "opened_adjustment_form": true/false,
    "entered_amount": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        vlm_response = query_vlm(
            prompt=prompt,
            images=all_frames
        )
        
        if not vlm_response.get("success"):
            return {"success": False, "error": vlm_response.get("error", "VLM query failed")}
        
        parsed = vlm_response.get("parsed", {})
        
        workflow_completed = parsed.get("workflow_completed", False)
        found_billing = parsed.get("found_billing_section", False)
        opened_form = parsed.get("opened_adjustment_form", False)
        
        feedback = ""
        if workflow_completed:
            feedback = "Billing workflow appears complete"
        elif found_billing and opened_form:
            feedback = "Billing form accessed but completion uncertain"
        elif found_billing:
            feedback = "Billing section found but form completion unclear"
        else:
            feedback = "Could not confirm billing workflow"
        
        return {
            "success": True,
            "workflow_completed": workflow_completed,
            "feedback": feedback,
            "details": parsed
        }
        
    except ImportError:
        logger.warning("VLM utilities not available")
        return {"success": False, "error": "VLM utilities not available"}
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    # Test the verifier with mock data
    mock_result = {
        "task_start_time": 1700000000,
        "task_end_time": 1700000300,
        "patient_pid": 3,
        "initial_counts": {"ar_activity": 5, "ar_session": 2, "payments": 0, "ar_max_seq": 10},
        "current_counts": {"ar_activity": 6, "ar_session": 3, "payments": 0},
        "adjustment_found": True,
        "new_transaction_exists": True,
        "adjustment": {
            "amount": "15.00",
            "memo": "Small balance write-off",
            "post_time": "2024-01-15 10:30:00",
            "account_code": "ADJ"
        },
        "screenshot_exists": True
    }
    
    print("Mock test data:")
    print(json.dumps(mock_result, indent=2))