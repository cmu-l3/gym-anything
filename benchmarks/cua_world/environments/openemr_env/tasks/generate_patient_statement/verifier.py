#!/usr/bin/env python3
"""
Verifier for Generate Patient Statement task in OpenEMR

Verification Strategy:
1. Check if agent logged in successfully
2. Check if correct patient (Jayson Fadel, pid=3) was accessed
3. Check if billing/fees section was accessed
4. Check if statement was viewed/generated
5. Use VLM to verify billing content visible in trajectory

Uses copy_from_env to read pre-exported verification data from the container.
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any, List, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_patient_statement(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the patient statement task was completed correctly.
    
    Scoring (100 points total):
    - Login completed: 10 points
    - Correct patient selected: 25 points  
    - Billing section accessed: 25 points
    - Statement viewed/generated: 30 points
    - VLM verification of billing content: 10 points
    
    Passing threshold: 60 points with correct patient accessed
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info including copy_from_env function
        task_info: Task info with task_id and metadata
        
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
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 3)
    expected_fname = metadata.get('patient_fname', 'Jayson')
    expected_lname = metadata.get('patient_lname', 'Fadel')
    
    score = 0
    feedback_parts = []
    subscores = {
        "login_completed": False,
        "correct_patient_selected": False,
        "billing_section_accessed": False,
        "statement_viewed": False,
        "vlm_verification": False
    }
    
    # Read exported result from container
    result = None
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/patient_statement_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
            logger.info(f"Loaded result data: {json.dumps(result, indent=2)}")
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        logger.error(f"Failed to read result file: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read verification data: {str(e)}"
        }
    
    if not result:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No verification data available"
        }
    
    # Extract activity detection data
    activity = result.get('activity_detection', {})
    output = result.get('output', {})
    patient_info = result.get('patient', {})
    billing_data = result.get('billing_data', {})
    environment = result.get('environment', {})
    
    # CRITERION 1: Login completed (10 points)
    login_detected = activity.get('login_detected', False)
    new_log_entries = activity.get('new_log_entries', 0)
    
    if login_detected or new_log_entries > 0:
        score += 10
        subscores["login_completed"] = True
        feedback_parts.append("✓ Login activity detected")
    else:
        feedback_parts.append("✗ No login activity detected")
    
    # CRITERION 2: Correct patient selected (25 points)
    patient_accessed = activity.get('patient_accessed', False)
    patient_access_count = activity.get('patient_access_log_count', 0)
    
    if patient_accessed or patient_access_count > 0:
        score += 25
        subscores["correct_patient_selected"] = True
        feedback_parts.append(f"✓ Patient {expected_fname} {expected_lname} (pid={expected_pid}) accessed")
    else:
        feedback_parts.append(f"✗ Patient access not confirmed for pid={expected_pid}")
    
    # CRITERION 3: Billing section accessed (25 points)
    billing_accessed = activity.get('billing_accessed', False)
    billing_access_count = activity.get('billing_access_log_count', 0)
    
    if billing_accessed or billing_access_count > 0:
        score += 25
        subscores["billing_section_accessed"] = True
        feedback_parts.append("✓ Billing/Fees section accessed")
    else:
        # Check window title for billing keywords
        window_title = environment.get('window_title', '').lower()
        billing_keywords = ['billing', 'fees', 'statement', 'ledger', 'payment', 'account']
        if any(kw in window_title for kw in billing_keywords):
            score += 20
            subscores["billing_section_accessed"] = True
            feedback_parts.append("✓ Billing section likely accessed (window title match)")
        else:
            feedback_parts.append("✗ Billing section access not confirmed")
    
    # CRITERION 4: Statement viewed/generated (30 points)
    statement_file_found = output.get('statement_file_found', False)
    screenshot_exists = output.get('screenshot_exists', False)
    
    # Check multiple indicators of statement viewing
    statement_viewed = False
    
    # Check if statement file was generated
    if statement_file_found:
        score += 30
        statement_viewed = True
        subscores["statement_viewed"] = True
        feedback_parts.append("✓ Statement file generated")
    elif billing_accessed and patient_accessed:
        # If billing was accessed for correct patient, likely viewed statement
        score += 20
        statement_viewed = True
        subscores["statement_viewed"] = True
        feedback_parts.append("△ Statement likely viewed (billing accessed for correct patient)")
    elif screenshot_exists and subscores["login_completed"]:
        # Partial credit if we have evidence of task progression
        score += 10
        feedback_parts.append("△ Task in progress, statement view unconfirmed")
    else:
        feedback_parts.append("✗ Statement viewing not confirmed")
    
    # CRITERION 5: VLM verification of billing content (10 points)
    vlm_score = verify_with_vlm(traj, env_info, expected_fname, expected_lname)
    if vlm_score > 0:
        score += vlm_score
        subscores["vlm_verification"] = True
        feedback_parts.append(f"✓ VLM confirmed billing/patient content visible (+{vlm_score}pts)")
    
    # Add billing data info to feedback
    record_count = billing_data.get('record_count', 0)
    total_fees = billing_data.get('total_fees', '0')
    if record_count > 0:
        feedback_parts.append(f"ℹ Patient has {record_count} billing records (${total_fees} total)")
    
    # Determine pass/fail
    # Must have accessed correct patient AND either billing or statement
    key_criteria_met = subscores["correct_patient_selected"] and (
        subscores["billing_section_accessed"] or subscores["statement_viewed"]
    )
    passed = score >= 60 and key_criteria_met
    
    # Cap score at 100
    score = min(score, 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "expected_patient": f"{expected_fname} {expected_lname} (pid={expected_pid})",
            "activity_summary": {
                "login": login_detected,
                "patient_access": patient_accessed,
                "billing_access": billing_accessed,
                "statement_file": statement_file_found
            },
            "task_duration_seconds": result.get('task_duration_seconds', 0)
        }
    }


def verify_with_vlm(traj: Dict[str, Any], env_info: Dict[str, Any], 
                    expected_fname: str, expected_lname: str) -> int:
    """
    Use VLM to verify billing content is visible in trajectory screenshots.
    
    Args:
        traj: Trajectory data with screenshots
        env_info: Environment info with query_vlm function
        expected_fname: Expected patient first name
        expected_lname: Expected patient last name
        
    Returns:
        Score from 0-10 based on VLM verification
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    # Get trajectory frames - prefer sampling across trajectory
    frames = []
    try:
        # Try to get frames from trajectory
        if 'frames' in traj and traj['frames']:
            all_frames = traj['frames']
            # Sample frames: first, middle, and last portions
            n_frames = len(all_frames)
            if n_frames >= 5:
                indices = [0, n_frames//4, n_frames//2, 3*n_frames//4, n_frames-1]
                frames = [all_frames[i] for i in indices if i < n_frames]
            else:
                frames = all_frames
        
        # Also try to get final screenshot
        episode_dir = traj.get('episode_dir', '')
        if episode_dir:
            final_screenshot = os.path.join(episode_dir, 'final_screenshot.png')
            if os.path.exists(final_screenshot):
                frames.append(final_screenshot)
    except Exception as e:
        logger.warning(f"Error getting trajectory frames: {e}")
    
    if not frames:
        logger.warning("No frames available for VLM verification")
        return 0
    
    # Use last few frames for verification (most likely to show result)
    frames_to_check = frames[-3:] if len(frames) >= 3 else frames
    
    vlm_prompt = f"""You are verifying if a computer agent successfully navigated to view a patient's billing statement in OpenEMR (Electronic Health Records system).

Expected patient: {expected_fname} {expected_lname}

Look at these screenshots and determine:
1. Is this OpenEMR or a medical records system interface?
2. Is the patient name "{expected_fname} {expected_lname}" visible anywhere?
3. Is there a billing, fees, or statement section visible?
4. Can you see financial information like charges, payments, balance, or dollar amounts?
5. Does this look like an account statement or billing summary?

Respond in JSON format:
{{
    "is_medical_system": true/false,
    "patient_name_visible": true/false,
    "billing_section_visible": true/false,
    "financial_data_visible": true/false,
    "looks_like_statement": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}}
"""
    
    try:
        # Query VLM with frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=frames_to_check
        )
        
        if not vlm_result.get('success'):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get('parsed', {})
        
        # Calculate score based on VLM findings
        vlm_score = 0
        
        if parsed.get('is_medical_system'):
            vlm_score += 2
        if parsed.get('patient_name_visible'):
            vlm_score += 3
        if parsed.get('billing_section_visible'):
            vlm_score += 2
        if parsed.get('financial_data_visible'):
            vlm_score += 2
        if parsed.get('looks_like_statement'):
            vlm_score += 1
        
        # Adjust for confidence
        confidence = parsed.get('confidence', 'low')
        if confidence == 'low':
            vlm_score = vlm_score // 2
        elif confidence == 'medium':
            vlm_score = int(vlm_score * 0.75)
        
        return min(vlm_score, 10)
        
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        return 0


if __name__ == "__main__":
    # Test mode - run basic verification checks
    print("Patient Statement Verifier - Test Mode")
    print("=" * 50)
    
    # Mock data for testing
    mock_result = {
        "task_start_timestamp": 1700000000,
        "task_end_timestamp": 1700000120,
        "task_duration_seconds": 120,
        "patient": {"pid": 3, "fname": "Jayson", "lname": "Fadel"},
        "billing_data": {"record_count": 4, "total_fees": "360.00"},
        "activity_detection": {
            "login_detected": True,
            "patient_accessed": True,
            "billing_accessed": True,
            "new_log_entries": 15,
            "patient_access_log_count": 3,
            "billing_access_log_count": 2,
            "login_log_count": 1
        },
        "output": {
            "statement_file_found": False,
            "screenshot_exists": True,
            "screenshot_size_bytes": 150000
        },
        "environment": {
            "firefox_running": True,
            "window_title": "Billing - OpenEMR"
        }
    }
    
    print("Mock verification result:")
    print(json.dumps(mock_result, indent=2))
    
    # Calculate expected score
    expected_score = 10 + 25 + 25 + 20  # login + patient + billing + partial statement
    print(f"\nExpected score (without VLM): {expected_score}")
    print("Test complete.")