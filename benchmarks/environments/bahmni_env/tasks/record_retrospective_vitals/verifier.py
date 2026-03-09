#!/usr/bin/env python3
"""
Verifier for record_retrospective_vitals task.

Verifies:
1. An observation for Weight (82kg) exists.
2. The observation was created DURING the task session.
3. The 'obsDatetime' (clinical date) is approx 10 days in the past.
4. The 'encounterDatetime' matches the observation date (consistency).
"""

import json
import os
import sys
import logging
import tempfile
from datetime import datetime, timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_openmrs_date(date_str):
    """Parse OpenMRS ISO8601-like dates (e.g. 2023-10-25T14:30:00.000+0000)."""
    if not date_str:
        return None
    try:
        # Python 3.7+ handles +0000, but simpler to strip timezone for comparison 
        # as we are looking for 'approximate days'
        clean_str = date_str.split('+')[0].split('.')[0]
        return datetime.strptime(clean_str, "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None

def verify_record_retrospective_vitals(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract Data
    observations = result.get('observations', [])
    task_start_ts = result.get('task_start_ts', 0)
    target_date_str = result.get('target_date_str', '')
    
    if not observations:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No weight observations found for the patient."
        }

    # Helper: Target Date Object
    try:
        target_date_obj = datetime.strptime(target_date_str, "%Y-%m-%d")
    except:
        # Fallback if parsing fails
        target_date_obj = datetime.now() - timedelta(days=10)

    task_start_dt = datetime.fromtimestamp(task_start_ts)
    
    # Find the BEST matching observation
    best_obs = None
    best_score = 0
    feedback_details = []

    for obs in observations:
        current_score = 0
        reasons = []

        # Check 1: Value (Max 20 pts)
        try:
            val = float(obs.get('value', 0))
        except:
            val = 0
        
        if abs(val - 82.0) < 0.1:
            current_score += 20
            reasons.append("Correct value (82kg)")
        else:
            reasons.append(f"Wrong value ({val}kg)")
            continue # Wrong value is not the target record

        # Check 2: Created During Task (Anti-Gaming)
        # We check 'dateCreated' against task_start_ts
        date_created = parse_openmrs_date(obs.get('dateCreated'))
        if date_created and date_created.timestamp() >= (task_start_ts - 120): # 2 min buffer
            # This is a new record
            pass 
        else:
            reasons.append("Old record (created before task)")
            # If strictly enforcing, we might skip. 
            # But let's check it anyway to provide feedback.
            # For scoring, we only count fresh records.
            continue 

        # Check 3: Retrospective Date (Max 60 pts)
        obs_datetime = parse_openmrs_date(obs.get('obsDatetime'))
        if obs_datetime:
            # Check difference in days
            diff = abs((obs_datetime.date() - target_date_obj.date()).days)
            
            if diff <= 1:
                current_score += 60
                reasons.append("Date is correct (~10 days ago)")
            elif diff > 8:
                # If date is basically "Today" (diff near 10 days from target), fail this check
                reasons.append(f"Date is wrong (Recorded for {obs_datetime.date()}, expected ~{target_date_obj.date()})")
            else:
                 reasons.append(f"Date is close but not exact ({diff} days off)")
        else:
            reasons.append("Could not parse observation date")

        # Check 4: Encounter Consistency (Max 20 pts)
        encounter = obs.get('encounter', {})
        enc_datetime = parse_openmrs_date(encounter.get('encounterDatetime'))
        
        if enc_datetime and obs_datetime:
            # Check if encounter date matches observation date (same day)
            if enc_datetime.date() == obs_datetime.date():
                current_score += 20
                reasons.append("Encounter date matches observation date")
            else:
                reasons.append("Inconsistent: Observation date != Encounter date")

        # Update best
        if current_score > best_score:
            best_score = current_score
            best_obs = obs
            feedback_details = reasons

    passed = best_score >= 80  # Must have Value (20) + Date (60)
    
    if best_obs:
        feedback = f"Best record found: {', '.join(feedback_details)}"
    else:
        feedback = "No valid record found matching criteria (82kg created during task)."

    return {
        "passed": passed,
        "score": best_score,
        "feedback": feedback
    }