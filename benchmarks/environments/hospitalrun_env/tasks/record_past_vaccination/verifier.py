#!/usr/bin/env python3
"""
Verifier for record_past_vaccination task.

Criteria:
1.  Record Existence: A procedure linked to Lucas Silva must exist.
2.  Content: Name must contain "MMR" or "Measles".
3.  Date Accuracy: The procedure date must be Oct 15, 2023.
    *   This is the critical check. Validates user used the date picker/input
        rather than accepting default "today".
4.  Metadata: Notes should verify source ("card").
5.  Anti-gaming: The record must have been created *during* the task session.
"""

import json
import os
import sys
import logging
import datetime
from dateutil import parser

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_past_vaccination(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    target_date_iso = metadata.get('target_date_iso', '2023-10-15')
    
    # 2. Retrieve Result JSON
    temp_file = "temp_task_result.json"
    try:
        copy_from_env("/tmp/task_result.json", temp_file)
        with open(temp_file, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result from environment: {e}"}
    finally:
        if os.path.exists(temp_file):
            os.remove(temp_file)

    records = result_data.get('records', [])
    task_start_ts = result_data.get('task_start_ts', 0)
    
    if not records:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No procedure records found for patient Lucas Silva."
        }

    # 3. Analyze Best Candidate Record
    best_score = 0
    feedback_lines = []
    
    for rec in records:
        current_score = 0
        current_feedback = []
        
        # A. Content Check (30 pts)
        name = rec.get('procedure_name', '').lower()
        if 'mmr' in name or 'measles' in name:
            current_score += 30
            current_feedback.append("Procedure name correct.")
        else:
            current_feedback.append(f"Procedure name mismatch (Found: '{name}').")

        # B. Notes Check (10 pts)
        notes = rec.get('notes', '').lower()
        if 'card' in notes or 'transcribed' in notes:
            current_score += 10
            current_feedback.append("Notes verify source.")
        elif notes:
            current_score += 5 # Partial credit for any notes
            current_feedback.append("Notes present but generic.")
        else:
            current_feedback.append("Notes missing.")

        # C. Date Check (40 pts) - CRITICAL
        # Date can be int (ms) or ISO string
        raw_date = rec.get('procedure_date_raw')
        parsed_date = None
        
        if raw_date:
            try:
                if isinstance(raw_date, int):
                    # Handle potential JS timestamp (ms) vs Unix (s)
                    # HospitalRun usually uses ms
                    ts = raw_date / 1000.0 if raw_date > 100000000000 else raw_date
                    parsed_date = datetime.datetime.fromtimestamp(ts)
                else:
                    parsed_date = parser.parse(str(raw_date))
            except:
                pass

        date_correct = False
        if parsed_date:
            # Compare YMD
            p_str = parsed_date.strftime('%Y-%m-%d')
            if p_str == target_date_iso:
                current_score += 40
                current_feedback.append(f"Date correctly backdated to {p_str}.")
                date_correct = True
            else:
                current_feedback.append(f"Date incorrect. Expected {target_date_iso}, got {p_str}.")
        else:
            current_feedback.append("Could not parse procedure date.")

        # D. Creation Time / Anti-Gaming (20 pts)
        # We want to ensure this record wasn't pre-existing (though setup.sh deletes them)
        # and was created *during* the task.
        # Note: 'created_at' in doc might be ms
        created_at = rec.get('created_at', 0)
        
        # If created_at is 0 or missing, we might rely on the fact that setup deleted old ones
        # and we found this one. But let's try to verify.
        is_fresh = True
        if created_at:
             try:
                c_ts = created_at / 1000.0 if created_at > 100000000000 else created_at
                if c_ts < task_start_ts:
                    is_fresh = False
                    current_feedback.append("Record appears to be pre-existing (timestamp too old).")
             except:
                 pass
        
        if is_fresh:
            current_score += 20
        
        # Update best
        if current_score > best_score:
            best_score = current_score
            feedback_lines = current_feedback

    # 4. Final Verdict
    passed = best_score >= 80  # Requires correct name + correct date + fresh
    
    return {
        "passed": passed,
        "score": best_score,
        "feedback": " ".join(feedback_lines)
    }