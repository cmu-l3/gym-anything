#!/usr/bin/env python3
"""
Verifier for admit_inpatient task in GNU Health.

Scoring breakdown (100 points total):
  - 25 pts: Any new inpatient record created
  - 20 pts: Target patient (Ana Betz) correctly assigned
  - 20 pts: Bed successfully assigned (not null)
  - 15 pts: Admission reason documented (contains keywords)
  - 10 pts: Hospitalization date set to today
  - 10 pts: Registration state moved past 'draft' to 'confirmed'/'hospitalized'

Pass threshold: score >= 60
"""

import json
import logging
import os
import tempfile
import datetime

logger = logging.getLogger(__name__)


def verify_admit_inpatient(traj, env_info, task_info):
    """Verify inpatient registration for Ana Betz."""
    copy_from_env = env_info.get('copy_from_env')
    metadata = task_info.get('metadata', {})

    score = 0
    feedback_parts = []
    subscores = {}

    # --- Retrieve result JSON from the container ---
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            local_path = tmp.name
        copy_from_env('/tmp/admit_inpatient_result.json', local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        logger.error(f"Failed to retrieve result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file from VM: {e}",
            "subscores": {}
        }

    task_start_time = result.get('task_start_time', 0)
    db_result = result.get('db_result', {})
    
    any_new = db_result.get('any_new_records_count', 0)
    target_found = db_result.get('target_record_found', False)
    target_record = db_result.get('target_record') or {}

    # --- Criterion 1: New inpatient record created (25 pts) ---
    if any_new > 0:
        score += 25
        subscores['new_record'] = 25
        feedback_parts.append(f"New inpatient record(s) created: {any_new}")
    else:
        subscores['new_record'] = 0
        feedback_parts.append("FAIL: No new inpatient registration records created")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # --- Criterion 2: Correct patient (Ana Betz) (20 pts) ---
    if target_found and target_record:
        score += 20
        subscores['correct_patient'] = 20
        feedback_parts.append("Correct patient (Ana Isabel Betz) registered")
    else:
        subscores['correct_patient'] = 0
        feedback_parts.append("FAIL: Record created but NOT for the correct patient (Ana Isabel Betz)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # Extract target record details
    bed_id = target_record.get('bed')
    hosp_date = target_record.get('hosp_date', '')
    state = target_record.get('state', 'draft')
    admission_reason = target_record.get('admission_reason', '') or ''
    create_ts = target_record.get('create_ts', 0)

    # --- Anti-gaming: Ensure it was created during the task ---
    if create_ts > 0 and task_start_time > 0 and create_ts < task_start_time - 10:
        score = 0
        feedback_parts.append("CRITICAL FAIL: Record creation timestamp is before task start (pre-existing data used)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts), "subscores": {}}

    # --- Criterion 3: Bed assigned (20 pts) ---
    if bed_id is not None:
        score += 20
        subscores['bed_assigned'] = 20
        feedback_parts.append(f"Bed assigned successfully (Bed ID: {bed_id})")
    else:
        subscores['bed_assigned'] = 0
        feedback_parts.append("No bed assigned to the registration")

    # --- Criterion 4: Admission reason documented (15 pts) ---
    reason_lower = admission_reason.lower()
    keywords = metadata.get('required_keywords', ["hydrogen sulfide", "exposure", "osha", "observation"])
    
    matches = sum(1 for kw in keywords if kw.lower() in reason_lower)
    
    if matches >= 2:
        score += 15
        subscores['admission_reason'] = 15
        feedback_parts.append("Admission reason properly documented with contextual keywords")
    elif len(reason_lower.strip()) > 5:
        score += 7
        subscores['admission_reason'] = 7
        feedback_parts.append("Admission reason present but missing specific expected exposure details (Partial credit)")
    else:
        subscores['admission_reason'] = 0
        feedback_parts.append("Admission reason missing or too short")

    # --- Criterion 5: Hospitalization date set (10 pts) ---
    # Convert dates to check if it's today (or yesterday to avoid timezone edge cases)
    today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
    yesterday = (datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=1)).strftime('%Y-%m-%d')
    
    if hosp_date == today or hosp_date == yesterday:
        score += 10
        subscores['date_set'] = 10
        feedback_parts.append(f"Hospitalization date correctly set ({hosp_date})")
    elif hosp_date:
        score += 5
        subscores['date_set'] = 5
        feedback_parts.append(f"Hospitalization date set but not today ({hosp_date})")
    else:
        subscores['date_set'] = 0
        feedback_parts.append("Hospitalization date not set")

    # --- Criterion 6: Registration state confirmed (10 pts) ---
    if state in ['confirmed', 'hospitalized', 'done']:
        score += 10
        subscores['registration_confirmed'] = 10
        feedback_parts.append(f"Registration status confirmed (state: {state})")
    else:
        subscores['registration_confirmed'] = 0
        feedback_parts.append(f"Registration saved but not confirmed (state: {state})")

    # --- Final Assessment ---
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }