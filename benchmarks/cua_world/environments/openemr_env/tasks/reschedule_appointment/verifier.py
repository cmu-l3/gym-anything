#!/usr/bin/env python3
"""
Verifier for Reschedule Appointment task in OpenEMR

Verifies that an existing appointment was properly rescheduled (moved, not duplicated)
from tomorrow at 10:00 AM to day after tomorrow at 2:30 PM.

Uses copy_from_env to read pre-exported verification data from the container.

Scoring (100 points total):
- New appointment exists at correct date/time: 30 points
- Correct new date (2 days from task start): 15 points  
- Correct new time (14:30 / 2:30 PM): 15 points
- Original slot cleared (10:00 AM tomorrow): 20 points
- Appointment details preserved (duration, etc.): 10 points
- Single appointment (not duplicated): 10 points

Pass threshold: 70 points with new_appointment_exists AND original_slot_cleared
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_reschedule_appointment(traj, env_info, task_info):
    """
    Verify that the appointment was correctly rescheduled.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info with copy_from_env function
        task_info: Task metadata
        
    Returns:
        dict with 'passed', 'score', 'feedback', 'subscores'
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
    expected_target_time = metadata.get('target_time', '14:30:00')
    scoring = metadata.get('scoring', {
        'new_appointment_exists': 30,
        'correct_new_date': 15,
        'correct_new_time': 15,
        'original_slot_cleared': 20,
        'details_preserved': 10,
        'single_appointment': 10
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/reschedule_appointment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
                
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error reading result: {e}"
        }
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    subscores = {
        "new_appointment_exists": False,
        "correct_new_date": False,
        "correct_new_time": False,
        "original_slot_cleared": False,
        "details_preserved": False,
        "single_appointment": False
    }
    
    # Extract data from result
    patient_pid = result.get('patient_pid', 0)
    original_date = result.get('original_date', '')
    target_date = result.get('target_date', '')
    new_appt = result.get('new_appointment', {})
    validation = result.get('validation', {})
    counts = result.get('counts', {})
    
    logger.info(f"Verifying reschedule: pid={patient_pid}")
    logger.info(f"Original date: {original_date}, Target date: {target_date}")
    logger.info(f"New appointment data: {new_appt}")
    logger.info(f"Validation flags: {validation}")
    
    # Verify correct patient
    if patient_pid != expected_pid:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Wrong patient ID: expected {expected_pid}, got {patient_pid}",
            "subscores": subscores
        }
    
    # CRITERION 1: New appointment exists at target date/time (30 points)
    new_appt_found = new_appt.get('found', False)
    if new_appt_found:
        score += scoring.get('new_appointment_exists', 30)
        subscores['new_appointment_exists'] = True
        feedback_parts.append(f"✓ Appointment found at new date/time (EID: {new_appt.get('eid', 'unknown')})")
    else:
        feedback_parts.append("✗ No appointment found at target date/time (day after tomorrow at 2:30 PM)")
        # Without new appointment, task fails
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }
    
    # CRITERION 2: Correct new date (15 points)
    appt_date = new_appt.get('date', '')
    date_correct = validation.get('date_correct', False)
    if date_correct or appt_date == target_date:
        score += scoring.get('correct_new_date', 15)
        subscores['correct_new_date'] = True
        feedback_parts.append(f"✓ Correct date: {appt_date}")
    else:
        feedback_parts.append(f"✗ Wrong date: expected {target_date}, got {appt_date}")
    
    # CRITERION 3: Correct new time (15 points)
    appt_time = new_appt.get('start_time', '')
    time_correct = validation.get('time_correct', False)
    if time_correct or '14:30' in appt_time:
        score += scoring.get('correct_new_time', 15)
        subscores['correct_new_time'] = True
        feedback_parts.append(f"✓ Correct time: {appt_time}")
    else:
        feedback_parts.append(f"✗ Wrong time: expected 14:30, got {appt_time}")
    
    # CRITERION 4: Original slot cleared (20 points) - CRITICAL for anti-gaming
    original_cleared = validation.get('original_slot_cleared', False)
    orig_slot_count = counts.get('original_slot_count', 1)
    if original_cleared or orig_slot_count == 0:
        score += scoring.get('original_slot_cleared', 20)
        subscores['original_slot_cleared'] = True
        feedback_parts.append("✓ Original time slot cleared (appointment was moved, not copied)")
    else:
        feedback_parts.append(f"✗ Original slot NOT cleared ({orig_slot_count} appointment(s) still at tomorrow 10:00 AM)")
        feedback_parts.append("  This suggests appointment was duplicated instead of rescheduled")
    
    # CRITERION 5: Details preserved (10 points)
    duration_preserved = validation.get('duration_preserved', False)
    appt_duration = new_appt.get('duration', '')
    if duration_preserved:
        score += scoring.get('details_preserved', 10)
        subscores['details_preserved'] = True
        feedback_parts.append(f"✓ Appointment details preserved (duration: {appt_duration})")
    else:
        # Try to verify duration manually
        try:
            dur_val = int(appt_duration) if appt_duration else 0
            # Check if duration is approximately 30 minutes (1800 sec or 30 min)
            if 1500 <= dur_val <= 2100 or 25 <= dur_val <= 35:
                score += scoring.get('details_preserved', 10)
                subscores['details_preserved'] = True
                feedback_parts.append(f"✓ Duration preserved: {appt_duration}")
            else:
                feedback_parts.append(f"✗ Duration may have changed: {appt_duration}")
        except (ValueError, TypeError):
            feedback_parts.append(f"? Could not verify duration: {appt_duration}")
    
    # CRITERION 6: Single appointment (10 points) - anti-duplication check
    single_appt = validation.get('single_appointment', False)
    total_count = counts.get('total_in_range', 0)
    if single_appt or total_count == 1:
        score += scoring.get('single_appointment', 10)
        subscores['single_appointment'] = True
        feedback_parts.append("✓ Single appointment in date range (no duplicates)")
    elif total_count == 0:
        feedback_parts.append("✗ No appointments found in date range (appointment may have been deleted)")
    else:
        feedback_parts.append(f"✗ Multiple appointments ({total_count}) in range - possible duplication")
    
    # Determine pass/fail
    # Must have: new appointment exists AND original slot cleared
    key_criteria_met = subscores['new_appointment_exists'] and subscores['original_slot_cleared']
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback_parts.insert(0, f"Score: {score}/100")
    if passed:
        feedback_parts.insert(1, "PASSED: Appointment successfully rescheduled")
    else:
        if not key_criteria_met:
            feedback_parts.insert(1, "FAILED: Must move appointment (not duplicate)")
        else:
            feedback_parts.insert(1, f"FAILED: Score {score} below threshold 70")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
        "details": {
            "original_date": original_date,
            "target_date": target_date,
            "new_appointment": new_appt,
            "validation": validation,
            "counts": counts
        }
    }


if __name__ == "__main__":
    # Test mode - for local debugging
    print("Verifier module for reschedule_appointment task")
    print("Run via task framework for actual verification")