#!/usr/bin/env python3
import json
import logging
import datetime
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_date(date_str):
    """
    Parse HospitalRun date strings.
    Usually ISO format: '2026-04-01T10:00:00.000Z' or '2026-04-01T13:00:00+03:00'
    Returns YYYY-MM-DD string.
    """
    if not date_str:
        return ""
    try:
        # Split on T to get date part, ignoring time/timezone for this check
        return date_str.split('T')[0]
    except Exception:
        return ""

def verify_schedule_antenatal_care_series(traj, env_info, task_info):
    """
    Verify that 4 specific ANC appointments were scheduled.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_appointments = metadata.get('expected_appointments', [])

    # 2. Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    found_appointments = result.get('appointments', [])
    task_start_time = result.get('task_start_time', 0)
    
    logger.info(f"Found {len(found_appointments)} appointments linked to patient.")

    # 3. Verification Logic
    score = 0
    feedback = []
    
    # We need to match found appointments to expected ones.
    # Since dates are unique in the requirement, we can map by date.
    
    found_map = {} # Date -> Appointment
    
    for appt in found_appointments:
        d_str = parse_date(appt.get('startDate', ''))
        if d_str:
            found_map[d_str] = appt
            
    # Iterate expectations
    matches_found = 0
    desc_matches = 0
    
    for expected in expected_appointments:
        target_date = expected['date']
        target_desc_kw = expected['desc_keyword']
        
        # Check for date match (exact match on YYYY-MM-DD required)
        if target_date in found_map:
            score += 20
            matches_found += 1
            appt = found_map[target_date]
            
            # Check description
            actual_desc = appt.get('description', '').lower()
            if target_desc_kw in actual_desc:
                # "anc visit 1" in "anc visit 1" -> True
                # Check the specific number to ensure they didn't just copy paste "ANC Visit"
                # The keyword in metadata includes the number (e.g. "anc visit 1")
                score += 2.5 # 10 points total for descriptions (2.5 * 4)
                desc_matches += 1
                feedback.append(f"✓ Found {target_date} ({actual_desc})")
            else:
                feedback.append(f"⚠ Found {target_date} but description mismatch ('{actual_desc}')")
        else:
            feedback.append(f"✗ Missing appointment for {target_date}")

    # Check for correct patient linkage (Implicitly done by export script, but award points for count)
    # If we found at least 4 appointments linked to the patient (even if dates wrong), give some points
    if len(found_appointments) >= 4:
        score += 10
        feedback.append("✓ At least 4 appointments linked to patient")
    elif len(found_appointments) > 0:
        score += 5
        feedback.append(f"⚠ Only {len(found_appointments)} appointments linked to patient")

    # Final tally
    passed = score >= 80  # Requires all dates correct + patient link, or dates + descriptions
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }