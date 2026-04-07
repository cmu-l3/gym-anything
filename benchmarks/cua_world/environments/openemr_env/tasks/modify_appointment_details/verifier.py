#!/usr/bin/env python3
"""
Verifier for Modify Appointment Details task in OpenEMR

Verifies that an existing appointment was properly modified:
- Duration changed from 15 to 30 minutes
- Category changed to Office Visit
- Comments updated with relevant text
- Date/time NOT changed (preserved)

Uses copy_from_env to read pre-exported verification data.
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_modify_appointment(traj, env_info, task_info):
    """
    Verify that the appointment was correctly modified.
    
    Scoring (100 points total):
    - Appointment still exists: 15 points
    - Correct patient (pid=2): 10 points
    - Duration changed to 30 minutes (1800s): 25 points
    - Category changed to Office Visit: 25 points
    - Comment updated with keywords: 15 points
    - Date/time preserved: 10 points
    
    Passing threshold: 70 points with duration changed
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available"
        }
    
    # Get expected values from metadata (with defaults)
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 2)
    expected_duration = metadata.get('expected_duration_seconds', 1800)
    initial_duration = metadata.get('initial_duration_seconds', 900)
    expected_start_time = metadata.get('appointment_start_time', '10:00:00')
    comment_keywords = metadata.get('expected_comment_keywords', ['additional', 'concerns', 'extended'])
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/modify_appointment_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "appointment_exists": False,
            "correct_patient": False,
            "duration_changed": False,
            "category_changed": False,
            "comment_updated": False,
            "datetime_preserved": False
        }
        
        # Extract data from result
        appt_exists = result.get('appointment_exists', False)
        initial_state = result.get('initial_state', {})
        current_state = result.get('current_state', {})
        changes = result.get('changes_detected', {})
        reference = result.get('reference', {})
        
        logger.info(f"Appointment exists: {appt_exists}")
        logger.info(f"Initial state: {initial_state}")
        logger.info(f"Current state: {current_state}")
        logger.info(f"Changes detected: {changes}")
        
        # CRITERION 1: Appointment still exists (15 points)
        if appt_exists:
            score += 15
            subscores["appointment_exists"] = True
            feedback_parts.append("✓ Appointment exists")
        else:
            feedback_parts.append("✗ Appointment not found - may have been deleted")
            return {
                "passed": False,
                "score": 0,
                "feedback": "Appointment was deleted instead of modified",
                "subscores": subscores
            }
        
        # CRITERION 2: Correct patient (10 points)
        current_pid = current_state.get('pid', '')
        try:
            current_pid_int = int(current_pid) if current_pid else 0
        except (ValueError, TypeError):
            current_pid_int = 0
            
        if current_pid_int == expected_pid:
            score += 10
            subscores["correct_patient"] = True
            feedback_parts.append(f"✓ Correct patient (pid={expected_pid})")
        else:
            feedback_parts.append(f"✗ Wrong patient: expected pid={expected_pid}, got {current_pid}")
        
        # CRITERION 3: Duration changed to 30 minutes (25 points)
        current_duration = current_state.get('duration', 0)
        try:
            current_duration_int = int(current_duration) if current_duration else 0
        except (ValueError, TypeError):
            current_duration_int = 0
        
        initial_dur = initial_state.get('duration', initial_duration)
        try:
            initial_dur_int = int(initial_dur) if initial_dur else initial_duration
        except (ValueError, TypeError):
            initial_dur_int = initial_duration
            
        if current_duration_int == expected_duration:
            # Exact match - full points
            score += 25
            subscores["duration_changed"] = True
            feedback_parts.append(f"✓ Duration correct: {current_duration_int // 60} minutes")
        elif current_duration_int > initial_dur_int:
            # Duration increased but not to exact value - partial credit
            score += 15
            subscores["duration_changed"] = "partial"
            feedback_parts.append(f"△ Duration increased to {current_duration_int // 60} min (expected 30 min)")
        else:
            feedback_parts.append(f"✗ Duration not changed: still {current_duration_int // 60} min (expected 30 min)")
        
        # CRITERION 4: Category changed to Office Visit (25 points)
        current_catid = current_state.get('catid', '')
        initial_catid = initial_state.get('catid', '')
        current_cat_name = current_state.get('category_name', '').lower()
        office_visit_catid = reference.get('office_visit_catid', '')
        
        category_is_office_visit = False
        if 'office' in current_cat_name:
            category_is_office_visit = True
        elif office_visit_catid and str(current_catid) == str(office_visit_catid):
            category_is_office_visit = True
        elif 'established' in current_cat_name:
            category_is_office_visit = True
            
        if category_is_office_visit:
            score += 25
            subscores["category_changed"] = True
            feedback_parts.append(f"✓ Category changed to Office Visit")
        elif str(current_catid) != str(initial_catid) and current_catid:
            # Category changed to something else - partial credit
            score += 15
            subscores["category_changed"] = "partial"
            feedback_parts.append(f"△ Category changed to '{current_cat_name}' (expected Office Visit)")
        else:
            feedback_parts.append(f"✗ Category not changed from Follow Up")
        
        # CRITERION 5: Comment updated with keywords (15 points)
        current_comment = current_state.get('comment', '').lower()
        keywords_found = []
        for keyword in comment_keywords:
            if keyword.lower() in current_comment:
                keywords_found.append(keyword)
        
        if len(keywords_found) >= 2:
            # Multiple relevant keywords found - full points
            score += 15
            subscores["comment_updated"] = True
            feedback_parts.append(f"✓ Comment updated with: {', '.join(keywords_found)}")
        elif len(keywords_found) >= 1:
            # At least one keyword - partial credit
            score += 10
            subscores["comment_updated"] = "partial"
            feedback_parts.append(f"△ Comment partially updated: found '{keywords_found[0]}'")
        elif current_comment and 'medication follow-up' not in current_comment:
            # Comment was changed but without expected keywords
            score += 5
            subscores["comment_updated"] = "minimal"
            feedback_parts.append(f"△ Comment modified but missing expected keywords")
        else:
            feedback_parts.append(f"✗ Comment not updated with relevant information")
        
        # CRITERION 6: Date/time preserved (10 points)
        # This is CRITICAL - the task specifically says NOT to change date/time
        current_date = current_state.get('date', '')
        current_start_time = current_state.get('start_time', '')
        expected_date = result.get('appointment_date', '')
        
        date_preserved = (current_date == expected_date)
        time_preserved = (current_start_time == expected_start_time)
        
        if date_preserved and time_preserved:
            score += 10
            subscores["datetime_preserved"] = True
            feedback_parts.append(f"✓ Date/time preserved: {current_date} {current_start_time}")
        elif date_preserved:
            score += 5
            subscores["datetime_preserved"] = "partial"
            feedback_parts.append(f"△ Date preserved but time changed: {current_start_time}")
        else:
            feedback_parts.append(f"✗ Date/time was changed (should remain {expected_date} {expected_start_time})")
            # Penalize since this violates task instructions
            score = max(0, score - 10)
        
        # Calculate final result
        # Pass requires: score >= 70 AND duration was changed (at least partially)
        duration_requirement_met = subscores["duration_changed"] in [True, "partial"]
        passed = score >= 70 and duration_requirement_met and subscores["appointment_exists"]
        
        # Build summary feedback
        summary = f"Score: {score}/100"
        if passed:
            summary = f"✓ PASSED - {summary}"
        else:
            if not duration_requirement_met:
                summary = f"✗ FAILED (duration not changed) - {summary}"
            else:
                summary = f"✗ FAILED - {summary}"
        
        feedback = f"{summary}\n" + "\n".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "initial_duration_seconds": initial_dur_int,
                "current_duration_seconds": current_duration_int,
                "initial_category": initial_catid,
                "current_category": current_catid,
                "current_category_name": current_state.get('category_name', ''),
                "datetime_preserved": subscores["datetime_preserved"],
                "comment_keywords_found": keywords_found
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {
                "appointment_exists": False,
                "correct_patient": False,
                "duration_changed": False,
                "category_changed": False,
                "comment_updated": False,
                "datetime_preserved": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {str(e)}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


if __name__ == "__main__":
    # Local testing stub
    print("Verifier module loaded successfully")
    print("Use verify_modify_appointment(traj, env_info, task_info) to verify")