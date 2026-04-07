#!/usr/bin/env python3
"""
Verifier for Send Internal Message task in OpenEMR

Verifies that an internal message was correctly sent to alert a provider
about patient Rosa Fritsch's elevated blood pressure.

Uses copy_from_env to read exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_send_internal_message(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the internal message was sent correctly.
    
    Scoring (100 points total):
    - Message created for correct patient (PID 4): 25 points
    - Message is newly created (count increased): 20 points
    - Message has valid recipient (provider): 20 points
    - Subject mentions BP/elevated/alert: 15 points
    - Body contains BP values 158 and 94: 15 points
    - Message requests review: 5 points
    
    Pass threshold: 75 points with message created and correct patient
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        Dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    # Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available for verification"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    expected_systolic = metadata.get('bp_systolic', '158')
    expected_diastolic = metadata.get('bp_diastolic', '94')
    
    # Scoring weights from metadata or defaults
    scoring = metadata.get('scoring', {})
    SCORE_MESSAGE_CREATED = scoring.get('message_created', 25)
    SCORE_CORRECT_PATIENT = scoring.get('correct_patient', 20)
    SCORE_CORRECT_RECIPIENT = scoring.get('correct_recipient', 20)
    SCORE_SUBJECT_VALID = scoring.get('subject_valid', 15)
    SCORE_BP_VALUES = scoring.get('bp_values_present', 15)
    SCORE_REVIEW_REQUESTED = scoring.get('review_requested', 5)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/send_message_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            logger.error(f"Failed to copy/read result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Could not read verification data: {str(e)}"
            }
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "message_created": False,
            "correct_patient": False,
            "newly_created": False,
            "correct_recipient": False,
            "subject_valid": False,
            "bp_values_present": False,
            "review_requested": False
        }
        
        # Extract data from result
        initial_msg_count = result.get('initial_patient_msg_count', 0)
        current_msg_count = result.get('current_patient_msg_count', 0)
        initial_total = result.get('initial_total_msg_count', 0)
        current_total = result.get('current_total_msg_count', 0)
        msg_found = result.get('new_message_found', False)
        message = result.get('message', {})
        recipient = result.get('recipient', {})
        content = result.get('content_validation', {})
        
        logger.info(f"Result: msg_found={msg_found}, initial={initial_msg_count}, current={current_msg_count}")
        logger.info(f"Message: {message}")
        logger.info(f"Content validation: {content}")
        
        # CRITERION 1: Message was created (25 points)
        if msg_found and current_msg_count > initial_msg_count:
            score += SCORE_MESSAGE_CREATED
            subscores["message_created"] = True
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ New message created (count: {initial_msg_count} → {current_msg_count})")
        elif msg_found:
            # Message found but count didn't increase - suspicious
            score += SCORE_MESSAGE_CREATED // 2
            subscores["message_created"] = True
            feedback_parts.append(f"⚠️ Message found but count unchanged (possible pre-existing message)")
        else:
            feedback_parts.append("❌ No new message found for patient")
            
            # Check if any message was created at all
            if current_total > initial_total:
                feedback_parts.append(f"   Note: {current_total - initial_total} message(s) created, but not for target patient")
            
            # Return early - no message means task not completed
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 2: Correct patient association (20 points)
        msg_pid = message.get('pid', '')
        try:
            msg_pid_int = int(msg_pid) if msg_pid else 0
        except (ValueError, TypeError):
            msg_pid_int = 0
            
        if msg_pid_int == expected_pid:
            score += SCORE_CORRECT_PATIENT
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Message correctly linked to patient PID {expected_pid}")
        else:
            feedback_parts.append(f"❌ Message linked to wrong patient (PID: {msg_pid}, expected: {expected_pid})")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: Valid recipient (20 points)
        assigned_to = message.get('assigned_to', '')
        recipient_name = recipient.get('name', '')
        is_provider = recipient.get('is_provider', False)
        
        if assigned_to and assigned_to.strip():
            if is_provider:
                score += SCORE_CORRECT_RECIPIENT
                subscores["correct_recipient"] = True
                feedback_parts.append(f"✅ Message assigned to provider: {recipient_name} ({assigned_to})")
            elif 'ho' in recipient_name.lower() or 'philip' in assigned_to.lower():
                # Specifically Dr. Philip Ho even if not marked as authorized
                score += SCORE_CORRECT_RECIPIENT
                subscores["correct_recipient"] = True
                feedback_parts.append(f"✅ Message assigned to Dr. Philip Ho ({assigned_to})")
            else:
                # Has recipient but not a provider
                score += SCORE_CORRECT_RECIPIENT // 2
                feedback_parts.append(f"⚠️ Message has recipient ({assigned_to}) but may not be a provider")
        else:
            feedback_parts.append("❌ Message has no recipient assigned")
        
        # CRITERION 4: Subject line contains BP reference (15 points)
        msg_title = message.get('title', '').lower()
        subject_keywords = ['bp', 'blood pressure', 'elevated', 'alert', 'hypertension']
        
        subject_has_keyword = any(kw in msg_title for kw in subject_keywords)
        if subject_has_keyword:
            score += SCORE_SUBJECT_VALID
            subscores["subject_valid"] = True
            feedback_parts.append(f"✅ Subject line contains BP/alert reference")
        elif 'rosa' in msg_title or 'fritsch' in msg_title:
            # Partial credit for mentioning patient name
            score += SCORE_SUBJECT_VALID // 2
            feedback_parts.append(f"⚠️ Subject mentions patient but not BP/alert")
        else:
            feedback_parts.append(f"❌ Subject doesn't mention BP/elevated/alert")
        
        # CRITERION 5: Body contains BP values (15 points)
        has_systolic = content.get('has_systolic_158', False)
        has_diastolic = content.get('has_diastolic_94', False)
        has_bp_keyword = content.get('has_bp_keyword', False)
        
        if has_systolic and has_diastolic:
            score += SCORE_BP_VALUES
            subscores["bp_values_present"] = True
            feedback_parts.append(f"✅ Message body contains BP values {expected_systolic}/{expected_diastolic}")
        elif has_systolic or has_diastolic:
            score += SCORE_BP_VALUES // 2
            feedback_parts.append(f"⚠️ Message contains partial BP (systolic={has_systolic}, diastolic={has_diastolic})")
        elif has_bp_keyword:
            score += SCORE_BP_VALUES // 3
            feedback_parts.append(f"⚠️ Message mentions BP but missing specific values")
        else:
            feedback_parts.append(f"❌ Message doesn't contain BP values")
        
        # CRITERION 6: Requests provider review (5 points)
        has_review = content.get('has_review_request', False)
        if has_review:
            score += SCORE_REVIEW_REQUESTED
            subscores["review_requested"] = True
            feedback_parts.append("✅ Message requests provider review")
        else:
            feedback_parts.append("⚠️ Message doesn't explicitly request review")
        
        # Determine pass/fail
        # Must have: message created + correct patient + some recipient + BP info
        key_criteria_met = (
            subscores["message_created"] and
            subscores["correct_patient"] and
            (subscores["correct_recipient"] or message.get('assigned_to')) and
            (subscores["bp_values_present"] or has_bp_keyword)
        )
        
        passed = score >= 75 and key_criteria_met
        
        # Final feedback
        feedback_parts.append(f"\n📊 Final Score: {score}/100")
        if passed:
            feedback_parts.append("✅ TASK PASSED")
        else:
            if score >= 60:
                feedback_parts.append("❌ TASK FAILED - Close but missing key criteria")
            else:
                feedback_parts.append("❌ TASK FAILED - Score below threshold")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "message_id": message.get('id'),
                "message_date": message.get('date'),
                "recipient": recipient_name or assigned_to,
                "patient_pid": msg_pid_int
            }
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON parsing error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Failed to parse verification data: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }


def verify_via_vlm(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Secondary VLM-based verification using trajectory screenshots.
    
    Checks if agent navigated through messaging workflow correctly.
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        return {"success": False, "error": "VLM not available"}
    
    # Import trajectory sampling (if available)
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        all_frames = frames + ([final] if final else [])
        
        prompt = """Analyze these screenshots from an OpenEMR session to verify the agent completed a messaging task.

TASK: Send an internal message about patient Rosa Fritsch's elevated blood pressure (158/94).

Look for evidence of:
1. Navigating to the Messages feature or messaging area
2. Creating/composing a new message
3. Selecting a recipient (provider)
4. Linking to a patient (Rosa Fritsch)
5. Entering message content about blood pressure
6. Sending/saving the message

Respond in JSON:
{
    "messages_accessed": true/false,
    "new_message_created": true/false,
    "recipient_selected": true/false,
    "patient_linked": true/false,
    "content_visible": true/false,
    "message_sent": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}"""
        
        vlm_result = query_vlm(prompt=prompt, images=all_frames)
        return vlm_result
        
    except ImportError:
        return {"success": False, "error": "VLM module not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}


if __name__ == "__main__":
    # Local testing
    print("Send Internal Message Verifier")
    print("Run via task framework for full verification")