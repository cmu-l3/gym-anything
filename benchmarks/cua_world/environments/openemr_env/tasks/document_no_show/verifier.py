#!/usr/bin/env python3
"""
Verifier for Document No-Show task in OpenEMR

This verifier checks that the agent:
1. Found the correct appointment for Mariana Altenwerth
2. Changed the appointment status to indicate no-show
3. Added documentation about contact attempts
4. Preserved the appointment date and time
5. Made changes during the task window (anti-gaming)

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_document_no_show(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the appointment was correctly marked as no-show with documentation.

    Scoring (100 points total):
    - Successful login/navigation (implied by modification): 10 points
    - Found correct appointment: 15 points
    - Status changed to no-show: 35 points
    - Contact attempts documented: 25 points
    - Comment contains contact keywords: 10 points
    - Appointment details preserved: 5 points

    Pass threshold: 70 points with status_is_noshow = True
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
    expected_pid = metadata.get('patient_pid', 2)
    expected_time = metadata.get('appointment_time', '09:00:00')
    initial_status = metadata.get('initial_status', '-')
    expected_status_codes = metadata.get('expected_status_codes', ['?', 'x', 'No Show', 'NS'])
    expected_keywords = metadata.get('expected_comment_keywords', ['called', 'voicemail', 'message', 'phone', 'contact', 'answer'])
    scoring = metadata.get('scoring', {})

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/document_noshow_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {
            "login_success": False,
            "found_appointment": False,
            "status_changed": False,
            "status_is_noshow": False,
            "comment_documented": False,
            "comment_has_keywords": False,
            "details_preserved": False,
            "modified_during_task": False
        }

        # Extract data from result
        current_state = result.get('current_state', {})
        initial_state = result.get('initial_state', {})
        verification = result.get('verification', {})
        task_timing = result.get('task_timing', {})

        appointment_found = current_state.get('appointment_found', False)
        current_status = current_state.get('status', '')
        current_comment = current_state.get('comment', '')
        current_date = current_state.get('date', '')
        current_start_time = current_state.get('start_time', '')
        modified_ts = current_state.get('modified_timestamp', 0)
        task_start = task_timing.get('start_timestamp', 0)

        logger.info(f"Verification data: found={appointment_found}, status='{current_status}', comment_len={len(current_comment)}")

        # CRITERION 1: Found correct appointment (15 points)
        if appointment_found:
            score += scoring.get('found_appointment', 15)
            subscores["found_appointment"] = True
            feedback_parts.append("✅ Found appointment for Mariana Altenwerth")
        else:
            feedback_parts.append("❌ Appointment not found in database")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Appointment for Mariana Altenwerth not found. Check if correct appointment was located.",
                "subscores": subscores
            }

        # CRITERION 2: Status changed to no-show (35 points)
        status_changed = verification.get('status_changed', False)
        status_is_noshow = verification.get('status_is_noshow', False)
        
        # Also check manually in case export script missed something
        if not status_is_noshow:
            status_lower = current_status.lower().strip()
            for expected_code in expected_status_codes:
                if expected_code.lower() in status_lower or status_lower == expected_code.lower():
                    status_is_noshow = True
                    break
            # Check for '?' specifically
            if current_status.strip() == '?':
                status_is_noshow = True

        if status_is_noshow:
            score += scoring.get('status_changed', 35)
            subscores["status_changed"] = True
            subscores["status_is_noshow"] = True
            feedback_parts.append(f"✅ Status changed to no-show ('{current_status}')")
        elif status_changed:
            # Status changed but not to no-show - partial credit
            score += scoring.get('status_changed', 35) // 2
            subscores["status_changed"] = True
            feedback_parts.append(f"⚠️ Status changed to '{current_status}' (expected no-show indicator like '?')")
        else:
            feedback_parts.append(f"❌ Status not changed (still '{current_status}', was '{initial_status}')")

        # CRITERION 3: Contact attempts documented (25 points)
        has_comment = verification.get('has_comment', False)
        if not has_comment and len(current_comment.strip()) > 10:
            has_comment = True

        if has_comment:
            score += scoring.get('comment_documented', 25)
            subscores["comment_documented"] = True
            # Truncate comment for display
            display_comment = current_comment[:60] + "..." if len(current_comment) > 60 else current_comment
            feedback_parts.append(f"✅ Comment documented: '{display_comment}'")
        else:
            feedback_parts.append("❌ No meaningful comment documenting contact attempts")

        # CRITERION 4: Comment contains contact keywords (10 points)
        comment_has_keywords = verification.get('comment_has_keywords', False)
        if not comment_has_keywords:
            comment_lower = current_comment.lower()
            for keyword in expected_keywords:
                if keyword.lower() in comment_lower:
                    comment_has_keywords = True
                    break

        if comment_has_keywords:
            score += scoring.get('comment_has_keywords', 10)
            subscores["comment_has_keywords"] = True
            feedback_parts.append("✅ Comment mentions contact attempt method")
        elif has_comment:
            feedback_parts.append("⚠️ Comment doesn't specifically mention contact method (called, voicemail, etc.)")

        # CRITERION 5: Appointment details preserved (5 points)
        details_preserved = verification.get('details_preserved', False)
        if not details_preserved:
            # Manual check
            from datetime import datetime
            today = datetime.now().strftime('%Y-%m-%d')
            if current_date == today and current_start_time == expected_time:
                details_preserved = True

        if details_preserved:
            score += scoring.get('details_preserved', 5)
            subscores["details_preserved"] = True
            feedback_parts.append("✅ Appointment date/time preserved correctly")
        else:
            feedback_parts.append(f"⚠️ Appointment details may have changed (date={current_date}, time={current_start_time})")

        # CRITERION 6: Login success (implied by modification) (10 points)
        modified_during_task = verification.get('modified_during_task', False)
        if not modified_during_task and modified_ts > 0 and task_start > 0:
            if modified_ts > task_start:
                modified_during_task = True

        if modified_during_task or status_changed or has_comment:
            score += scoring.get('login_success', 10)
            subscores["login_success"] = True
            subscores["modified_during_task"] = modified_during_task
            feedback_parts.append("✅ Successfully logged in and modified appointment")
        else:
            feedback_parts.append("❌ No evidence of appointment modification during task")

        # Anti-gaming check: must have been modified during the task
        if not modified_during_task and not status_changed and not has_comment:
            feedback_parts.append("⚠️ ANTI-GAMING: No changes detected during task window")
            # Don't fail outright, but this is suspicious

        # Calculate pass/fail
        # Must have status changed to no-show to pass
        key_criteria_met = subscores["status_is_noshow"]
        passed = score >= 70 and key_criteria_met

        return {
            "passed": passed,
            "score": score,
            "max_score": 100,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "appointment_status": current_status,
                "comment_length": len(current_comment),
                "status_changed": status_changed,
                "modified_timestamp": modified_ts,
                "task_start_timestamp": task_start
            }
        }

    except FileNotFoundError as e:
        logger.error(f"Result file not found: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification data not found. Export may have failed: {e}",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        logger.error(f"Failed to parse result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse verification data: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification failed with exception: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


# For local testing
if __name__ == "__main__":
    import subprocess
    
    def test_copy(src, dst):
        """Test copy function that copies from local paths."""
        subprocess.run(["cp", src, dst], check=True)
    
    # Mock trajectory and env_info
    mock_traj = {"frames": [], "steps": []}
    mock_env_info = {"copy_from_env": test_copy}
    mock_task_info = {
        "metadata": {
            "patient_pid": 2,
            "appointment_time": "09:00:00",
            "initial_status": "-",
            "expected_status_codes": ["?", "x", "No Show", "NS"],
            "expected_comment_keywords": ["called", "voicemail", "message", "phone", "contact", "answer"],
            "scoring": {
                "login_success": 10,
                "found_appointment": 15,
                "status_changed": 35,
                "comment_documented": 25,
                "comment_has_keywords": 10,
                "details_preserved": 5
            }
        }
    }
    
    result = verify_document_no_show(mock_traj, mock_env_info, mock_task_info)
    print(json.dumps(result, indent=2))