#!/usr/bin/env python3
"""
Verifier for Send Portal Message task in OpenEMR

Verification Strategy:
1. PRIMARY: Database check for new message to patient
2. SECONDARY: VLM trajectory verification for workflow confirmation

Scoring:
- Message exists for correct patient: 25 points
- Correct patient association: 20 points  
- Subject contains lab reference: 15 points
- Body has lab results mention: 10 points
- Body has follow-up/schedule request: 10 points
- Body has phone number: 10 points
- Message sent (not draft): 10 points

Total: 100 points
Pass threshold: 60 points with message_exists
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_send_portal_message(traj, env_info, task_info):
    """
    Verify that a portal message was sent to patient Jayson Fadel.
    
    Args:
        traj: Trajectory data with frames and steps
        env_info: Environment info including copy_from_env function
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
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    expected_phone = metadata.get('phone_number', '555-0100')
    scoring_weights = metadata.get('scoring_weights', {})
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/send_portal_message_result.json", temp_result.name)
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
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "message_exists": False,
        "correct_patient": False,
        "subject_correct": False,
        "body_has_lab": False,
        "body_has_followup": False,
        "body_has_phone": False,
        "message_sent": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    message_found = result.get('message_found', False)
    message = result.get('message', {})
    validation = result.get('validation', {})
    counts = result.get('counts', {})
    
    logger.info(f"Verification data: pid={patient_pid}, found={message_found}")
    logger.info(f"Message: {message}")
    logger.info(f"Validation: {validation}")
    
    # CRITERION 1: Message exists (25 points)
    if message_found:
        score += scoring_weights.get('message_exists', 25)
        subscores["message_exists"] = True
        feedback_parts.append(f"✅ Message found in {message.get('table', 'database')}")
    else:
        feedback_parts.append("❌ No message found for patient")
        
        # Check if any new entries were created at all
        pnotes_diff = counts.get('current_pnotes', 0) - counts.get('initial_pnotes', 0)
        portal_diff = counts.get('current_portal_msg', 0) - counts.get('initial_portal_msg', 0)
        mail_diff = counts.get('current_onsite_mail', 0) - counts.get('initial_onsite_mail', 0)
        
        if pnotes_diff > 0 or portal_diff > 0 or mail_diff > 0:
            feedback_parts.append(f"Note: Some messages were created but may not match patient")
        
        # Early return - no message means task failed
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: Correct patient (20 points)
    if patient_pid == expected_pid:
        score += scoring_weights.get('correct_patient', 20)
        subscores["correct_patient"] = True
        feedback_parts.append(f"✅ Message sent to correct patient (pid={expected_pid})")
    else:
        feedback_parts.append(f"❌ Wrong patient (expected pid={expected_pid}, got {patient_pid})")
        # Wrong patient is a critical failure
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 3: Subject contains lab reference (15 points)
    subject = message.get('subject', '')
    subject_has_lab = validation.get('subject_has_lab', False)
    subject_has_followup = validation.get('subject_has_followup', False)
    
    if subject_has_lab or subject_has_followup:
        score += scoring_weights.get('subject_correct', 15)
        subscores["subject_correct"] = True
        feedback_parts.append(f"✅ Subject appropriate: '{subject[:50]}...' " if len(subject) > 50 else f"✅ Subject appropriate: '{subject}'")
    else:
        # Do our own check in case export missed it
        subject_lower = subject.lower()
        if 'lab' in subject_lower or 'result' in subject_lower or 'follow' in subject_lower:
            score += scoring_weights.get('subject_correct', 15)
            subscores["subject_correct"] = True
            feedback_parts.append(f"✅ Subject contains relevant keywords")
        else:
            feedback_parts.append(f"❌ Subject missing lab/follow-up reference: '{subject[:30]}'")
    
    # CRITERION 4: Body has lab results mention (10 points)
    body_has_lab = validation.get('body_has_lab', False)
    if body_has_lab:
        score += scoring_weights.get('body_has_lab_reference', 10)
        subscores["body_has_lab"] = True
        feedback_parts.append("✅ Message body mentions lab results")
    else:
        # Double check
        body = message.get('body', '').lower()
        if 'lab' in body or 'result' in body or 'test' in body:
            score += scoring_weights.get('body_has_lab_reference', 10)
            subscores["body_has_lab"] = True
            feedback_parts.append("✅ Message body mentions lab results")
        else:
            feedback_parts.append("❌ Message body missing lab results reference")
    
    # CRITERION 5: Body has follow-up/schedule request (10 points)
    body_has_schedule = validation.get('body_has_schedule', False)
    if body_has_schedule:
        score += scoring_weights.get('body_has_followup_request', 10)
        subscores["body_has_followup"] = True
        feedback_parts.append("✅ Message mentions scheduling/follow-up")
    else:
        body = message.get('body', '').lower()
        if 'schedule' in body or 'appointment' in body or 'follow' in body or 'call' in body:
            score += scoring_weights.get('body_has_followup_request', 10)
            subscores["body_has_followup"] = True
            feedback_parts.append("✅ Message mentions scheduling/follow-up")
        else:
            feedback_parts.append("❌ Message missing scheduling/follow-up request")
    
    # CRITERION 6: Body has phone number (10 points)
    body_has_phone = validation.get('body_has_phone', False)
    if body_has_phone:
        score += scoring_weights.get('body_has_phone', 10)
        subscores["body_has_phone"] = True
        feedback_parts.append(f"✅ Message includes phone number ({expected_phone})")
    else:
        # Check for phone number pattern
        body = message.get('body', '')
        phone_pattern = re.compile(r'555[\s\-\.]?0100|555.?0100')
        if phone_pattern.search(body):
            score += scoring_weights.get('body_has_phone', 10)
            subscores["body_has_phone"] = True
            feedback_parts.append(f"✅ Message includes phone number")
        else:
            # Check for any phone number
            any_phone = re.compile(r'\d{3}[\s\-\.]?\d{4}')
            if any_phone.search(body):
                score += scoring_weights.get('body_has_phone', 10) // 2  # Half credit
                feedback_parts.append("⚠️ Message has a phone number (not expected one)")
            else:
                feedback_parts.append(f"❌ Message missing phone number ({expected_phone})")
    
    # CRITERION 7: Message sent (not draft) (10 points)
    is_sent = validation.get('is_sent_not_draft', False)
    status = message.get('status', '')
    
    if is_sent:
        score += scoring_weights.get('message_sent_not_draft', 10)
        subscores["message_sent"] = True
        feedback_parts.append("✅ Message was sent (not draft)")
    else:
        # If status is empty or unknown, assume sent
        status_lower = status.lower() if status else ''
        if not status_lower or status_lower not in ['draft', 'unsent', '0']:
            score += scoring_weights.get('message_sent_not_draft', 10)
            subscores["message_sent"] = True
            feedback_parts.append("✅ Message appears to be sent")
        else:
            feedback_parts.append(f"❌ Message is in draft status: '{status}'")
    
    # VLM Trajectory Verification (bonus check)
    vlm_result = verify_with_vlm(traj, env_info)
    if vlm_result.get('verified'):
        feedback_parts.append("✅ VLM confirms messaging workflow")
    elif vlm_result.get('error'):
        feedback_parts.append(f"⚠️ VLM verification unavailable")
    
    # Determine pass/fail
    # Must have message_exists and correct_patient at minimum
    key_criteria_met = subscores["message_exists"] and subscores["correct_patient"]
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "message_table": message.get('table', ''),
            "message_id": message.get('id', ''),
            "subject": message.get('subject', '')[:100],
            "patient_pid": patient_pid
        }
    }


def verify_with_vlm(traj, env_info):
    """
    Use VLM to verify the messaging workflow was followed.
    
    Uses trajectory frames to confirm:
    1. Agent navigated to patient
    2. Agent accessed messaging
    3. Agent composed message
    4. Agent sent message
    """
    try:
        # Try to import VLM utilities
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            return {"verified": False, "error": "VLM not available"}
        
        # Get trajectory frames
        frames = traj.get('frames', [])
        if not frames:
            return {"verified": False, "error": "No trajectory frames"}
        
        # Sample frames across trajectory
        num_frames = len(frames)
        if num_frames >= 5:
            # Sample 5 frames evenly distributed
            indices = [0, num_frames//4, num_frames//2, 3*num_frames//4, num_frames-1]
            sample_frames = [frames[i] for i in indices if i < num_frames]
        else:
            sample_frames = frames
        
        # Get final frame
        final_frame = frames[-1] if frames else None
        
        if not final_frame:
            return {"verified": False, "error": "No final frame"}
        
        # VLM prompt for verification
        prompt = """You are verifying if a computer agent successfully sent a patient portal message in OpenEMR.

TASK: Send a message to patient Jayson Fadel about lab results and scheduling a follow-up.

Looking at these screenshots from the task execution, determine:
1. Did the agent navigate to a patient record or patient context?
2. Did the agent access a messaging or communication feature?
3. Is there evidence of composing a message (text entry)?
4. Does the final state show a success message or sent confirmation?

Respond in JSON format:
{
    "patient_context_visible": true/false,
    "messaging_interface_accessed": true/false,
    "message_composed": true/false,
    "success_indicator": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        # Query VLM with trajectory frames
        vlm_response = query_vlm(
            prompt=prompt,
            images=sample_frames + [final_frame]
        )
        
        if not vlm_response.get('success'):
            return {"verified": False, "error": vlm_response.get('error', 'VLM query failed')}
        
        parsed = vlm_response.get('parsed', {})
        
        # Consider verified if at least 2 indicators are positive
        indicators = [
            parsed.get('patient_context_visible', False),
            parsed.get('messaging_interface_accessed', False),
            parsed.get('message_composed', False),
            parsed.get('success_indicator', False)
        ]
        
        positive_count = sum(1 for i in indicators if i)
        verified = positive_count >= 2
        
        return {
            "verified": verified,
            "confidence": parsed.get('confidence', 'low'),
            "reasoning": parsed.get('reasoning', ''),
            "indicators": {
                "patient_context": parsed.get('patient_context_visible', False),
                "messaging_accessed": parsed.get('messaging_interface_accessed', False),
                "message_composed": parsed.get('message_composed', False),
                "success_shown": parsed.get('success_indicator', False)
            }
        }
        
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return {"verified": False, "error": str(e)}


# For testing
if __name__ == "__main__":
    # Test with mock data
    mock_result = {
        "patient_pid": 3,
        "message_found": True,
        "message": {
            "table": "pnotes",
            "id": "123",
            "subject": "Lab Results - Please Schedule Follow-up",
            "body": "Your lab results are ready. Please call us at 555-0100 to schedule a follow-up appointment.",
            "status": "sent",
            "date": "2024-01-15"
        },
        "validation": {
            "subject_has_lab": True,
            "subject_has_followup": True,
            "body_has_lab": True,
            "body_has_schedule": True,
            "body_has_phone": True,
            "is_sent_not_draft": True
        },
        "counts": {
            "initial_pnotes": 0,
            "current_pnotes": 1
        }
    }
    
    print("Test verification would score this message highly")
    print(f"Subject: {mock_result['message']['subject']}")
    print(f"Body: {mock_result['message']['body']}")