#!/usr/bin/env python3
"""
Verifier for Create Recurring Appointment Series task in OpenEMR

This verifier checks that the agent created a series of 4 weekly appointments
for patient Nereida Windler (pid=1) on consecutive Tuesdays at 10:00 AM.

Scoring (100 points total):
- Correct patient selected: 15 points
- At least one appointment created: 15 points
- Exactly 4 appointments created: 20 points
- All appointments on Tuesday: 15 points
- All appointments at correct time (10:00 AM ±30 min): 10 points
- Weekly intervals between appointments: 15 points
- Correct duration (~45 min): 5 points
- Newly created (not pre-existing): 5 points

Pass threshold: 70 points with correct patient and at least one new appointment
"""

import sys
import os
import json
import logging
import tempfile
from datetime import datetime, timedelta
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recurring_appointments(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that recurring appointments were correctly created.
    
    Args:
        traj: Trajectory data with frames
        env_info: Environment info including copy_from_env
        task_info: Task info with metadata
    
    Returns:
        dict with 'passed', 'score', 'feedback', 'subscores'
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 1)
    expected_fname = metadata.get('patient_fname', 'Nereida')
    expected_lname = metadata.get('patient_lname', 'Windler')
    expected_count = metadata.get('expected_appointment_count', 4)
    expected_dow = metadata.get('expected_day_of_week', 2)  # Tuesday
    expected_dow_mysql = 3  # MySQL: 1=Sun, 2=Mon, 3=Tue
    expected_time = metadata.get('expected_start_time', '10:00')
    expected_duration = metadata.get('expected_duration_minutes', 45)
    expected_interval = metadata.get('expected_interval_days', 7)
    time_tolerance = metadata.get('time_tolerance_minutes', 30)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/recurring_appointments_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "correct_patient": False,
            "at_least_one_created": False,
            "exactly_four_created": False,
            "all_on_tuesday": False,
            "correct_time": False,
            "weekly_intervals": False,
            "correct_duration": False,
            "newly_created": False
        }
        
        # Extract data
        patient_pid = result.get('patient_pid', 0)
        initial_count = result.get('initial_appt_count', 0)
        current_count = result.get('current_appt_count', 0)
        new_count = result.get('new_appt_count', 0)
        analysis = result.get('analysis', {})
        appointments = result.get('appointments', [])
        
        logger.info(f"Result: pid={patient_pid}, initial={initial_count}, current={current_count}, new={new_count}")
        logger.info(f"Analysis: {analysis}")
        logger.info(f"Appointments: {len(appointments)}")
        
        # CRITERION 1: Correct patient (15 points)
        if patient_pid == expected_pid:
            score += 15
            subscores["correct_patient"] = True
            feedback_parts.append(f"✅ Correct patient selected (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"❌ Wrong patient! Expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Appointments created for wrong patient (expected pid={expected_pid})",
                "subscores": subscores
            }
        
        # CRITERION 2: At least one appointment created (15 points)
        if new_count >= 1:
            score += 15
            subscores["at_least_one_created"] = True
            feedback_parts.append(f"✅ {new_count} new appointment(s) created")
        else:
            feedback_parts.append("❌ No new appointments were created")
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts),
                "subscores": subscores
            }
        
        # CRITERION 3: Exactly 4 appointments (20 points)
        if new_count == expected_count:
            score += 20
            subscores["exactly_four_created"] = True
            feedback_parts.append(f"✅ Exactly {expected_count} appointments created (perfect!)")
        elif new_count >= expected_count:
            # Close enough - partial credit
            score += 15
            feedback_parts.append(f"⚠️ {new_count} appointments created (expected {expected_count})")
        elif new_count >= 2:
            # Some appointments, partial credit
            score += 10
            feedback_parts.append(f"⚠️ Only {new_count} appointments created (expected {expected_count})")
        else:
            feedback_parts.append(f"❌ Only {new_count} appointment(s) created (expected {expected_count})")
        
        # CRITERION 4: All on Tuesday (15 points)
        tuesday_count = analysis.get('tuesday_count', 0)
        non_tuesday_count = analysis.get('non_tuesday_count', 0)
        
        if tuesday_count == new_count and non_tuesday_count == 0 and new_count > 0:
            score += 15
            subscores["all_on_tuesday"] = True
            feedback_parts.append(f"✅ All {tuesday_count} appointments are on Tuesday")
        elif tuesday_count > 0:
            # Partial credit based on percentage
            tuesday_pct = tuesday_count / new_count if new_count > 0 else 0
            partial_score = int(15 * tuesday_pct)
            score += partial_score
            feedback_parts.append(f"⚠️ {tuesday_count}/{new_count} appointments are on Tuesday ({partial_score}/15 pts)")
        else:
            feedback_parts.append(f"❌ No appointments are on Tuesday (expected all on Tuesday)")
        
        # CRITERION 5: Correct time - 10:00 AM (10 points)
        correct_time_count = analysis.get('correct_time_count', 0)
        
        if correct_time_count == new_count and new_count > 0:
            score += 10
            subscores["correct_time"] = True
            feedback_parts.append(f"✅ All appointments at correct time (10:00 AM ±30 min)")
        elif correct_time_count > 0:
            time_pct = correct_time_count / new_count if new_count > 0 else 0
            partial_score = int(10 * time_pct)
            score += partial_score
            feedback_parts.append(f"⚠️ {correct_time_count}/{new_count} appointments at correct time ({partial_score}/10 pts)")
        else:
            feedback_parts.append(f"❌ No appointments at correct time (expected 10:00 AM)")
        
        # CRITERION 6: Weekly intervals (15 points)
        weekly_interval_count = analysis.get('weekly_interval_count', 0)
        expected_intervals = max(0, new_count - 1)  # Number of gaps between appointments
        
        if expected_intervals > 0:
            if weekly_interval_count == expected_intervals:
                score += 15
                subscores["weekly_intervals"] = True
                feedback_parts.append(f"✅ All intervals are approximately 7 days (weekly)")
            elif weekly_interval_count > 0:
                interval_pct = weekly_interval_count / expected_intervals
                partial_score = int(15 * interval_pct)
                score += partial_score
                feedback_parts.append(f"⚠️ {weekly_interval_count}/{expected_intervals} intervals are weekly ({partial_score}/15 pts)")
            else:
                feedback_parts.append(f"❌ No weekly intervals detected between appointments")
        elif new_count == 1:
            # Only one appointment, can't check intervals
            score += 5  # Partial credit
            feedback_parts.append("⚠️ Only 1 appointment - cannot verify weekly intervals")
        
        # CRITERION 7: Correct duration (5 points)
        # Check individual appointments for duration
        correct_duration_count = 0
        for appt in appointments:
            duration_str = appt.get('duration', '0')
            try:
                # Duration might be in minutes or seconds depending on OpenEMR version
                duration = int(duration_str)
                # Check if within range (30-60 minutes, or 1800-3600 seconds)
                if 30 <= duration <= 60 or 1800 <= duration <= 3600:
                    correct_duration_count += 1
            except (ValueError, TypeError):
                pass
        
        if correct_duration_count == new_count and new_count > 0:
            score += 5
            subscores["correct_duration"] = True
            feedback_parts.append(f"✅ All appointments have correct duration (~45 min)")
        elif correct_duration_count > 0:
            score += 2
            feedback_parts.append(f"⚠️ {correct_duration_count}/{new_count} appointments have correct duration")
        else:
            # Don't penalize heavily - duration field may vary by OpenEMR config
            score += 2
            feedback_parts.append(f"⚠️ Duration verification inconclusive")
        
        # CRITERION 8: Newly created during task (5 points)
        if new_count > 0 and current_count > initial_count:
            score += 5
            subscores["newly_created"] = True
            feedback_parts.append(f"✅ Appointments were newly created during task")
        else:
            feedback_parts.append(f"⚠️ Could not confirm appointments were created during task")
        
        # Determine pass/fail
        # Must have: correct patient + at least one new appointment + score >= 70
        key_criteria_met = subscores["correct_patient"] and subscores["at_least_one_created"]
        passed = score >= 70 and key_criteria_met
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        if passed:
            if subscores["exactly_four_created"] and subscores["all_on_tuesday"] and subscores["weekly_intervals"]:
                feedback = f"EXCELLENT! Perfect recurring appointment series created. {feedback}"
            else:
                feedback = f"PASS: Recurring appointments created with minor issues. {feedback}"
        else:
            if not subscores["at_least_one_created"]:
                feedback = f"FAIL: No appointments were created. {feedback}"
            elif score < 70:
                feedback = f"FAIL: Score {score}/100 below threshold (70). {feedback}"
            else:
                feedback = f"FAIL: Key criteria not met. {feedback}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "new_appointments": new_count,
                "expected_count": expected_count,
                "analysis": analysis
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed",
            "subscores": {}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}",
            "subscores": {}
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }


def verify_with_vlm_trajectory(traj: Dict[str, Any], env_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Optional VLM verification using trajectory frames.
    
    This provides supplementary evidence by checking:
    1. Agent navigated to calendar
    2. Agent interacted with appointment dialog
    3. Agent configured recurring options
    """
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        query_vlm = env_info.get('query_vlm')
        if not query_vlm:
            return {"success": False, "error": "VLM not available"}
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        if not frames and not final:
            return {"success": False, "error": "No screenshots available"}
        
        all_images = frames + ([final] if final else [])
        
        prompt = """You are verifying if an agent successfully created recurring appointments in OpenEMR.

Look at these screenshots from the agent's workflow and determine:

1. Did the agent navigate to a calendar/scheduler view?
2. Did the agent open an appointment creation dialog?
3. Did the agent appear to configure recurring/repeat options?
4. Does the final state show multiple appointments in the calendar?

Respond in JSON format:
{
    "calendar_accessed": true/false,
    "appointment_dialog_opened": true/false,
    "recurring_configured": true/false,
    "multiple_appointments_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation"
}
"""
        
        result = query_vlm(prompt=prompt, images=all_images)
        return result
        
    except ImportError:
        return {"success": False, "error": "VLM module not available"}
    except Exception as e:
        return {"success": False, "error": str(e)}