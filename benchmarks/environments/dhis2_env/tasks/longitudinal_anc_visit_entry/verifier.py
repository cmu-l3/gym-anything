#!/usr/bin/env python3
"""
Verifier for longitudinal_anc_visit_entry task.

Criteria:
1. Patient 'Hawa Jalloh' created after task start (20 pts)
2. Enrolled in correct Program and Org Unit (10 pts)
3. 3 Events created (20 pts)
4. Event dates match expected dates (20 pts)
5. Clinical data (Weight, BP) matches expected values (20 pts)
6. Events are Completed (10 pts)

Pass threshold: 70 points
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_longitudinal_anc_visit_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_visits = metadata.get('visits', [])
    
    # Copy result file
    temp_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/longitudinal_anc_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback = []
    
    # 1. Check Patient Existence (20 pts)
    if not result.get('patient_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Patient 'Hawa Jalloh' not found or not created during task."
        }
    
    score += 20
    feedback.append("Patient created (+20)")
    
    data = result.get('data', {})
    enrollments = data.get('enrollments') or []
    
    if not enrollments:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Patient found but not enrolled in any program."
        }

    # Find relevant enrollment (ANC)
    anc_enrollment = None
    for enroll in enrollments:
        prog_name = enroll.get('program', '').lower()
        if 'antenatal' in prog_name or 'mnch' in prog_name or 'anc' in prog_name:
            anc_enrollment = enroll
            break
            
    # 2. Check Enrollment Details (10 pts)
    if anc_enrollment:
        org_unit = anc_enrollment.get('org_unit', '')
        if 'Ngelehun' in org_unit:
            score += 10
            feedback.append("Correctly enrolled in ANC at Ngelehun CHC (+10)")
        else:
            score += 5
            feedback.append(f"Enrolled in ANC but wrong facility: {org_unit} (+5)")
    else:
        feedback.append("Not enrolled in ANC program")
        return {"passed": False, "score": score, "feedback": "; ".join(feedback)}

    # 3. Check Events (20 pts for count, 10 for completion)
    events = anc_enrollment.get('events') or []
    # Sort events by date
    events.sort(key=lambda x: x.get('date', ''))
    
    # Filter out empty/deleted events if any
    valid_events = [e for e in events if e.get('date')]
    
    if len(valid_events) >= 3:
        score += 20
        feedback.append(f"Found {len(valid_events)} visits (+20)")
    elif len(valid_events) > 0:
        partial = int(20 * (len(valid_events) / 3))
        score += partial
        feedback.append(f"Found {len(valid_events)}/3 visits (+{partial})")
    else:
        feedback.append("No visits found")

    # Check status
    completed_count = sum(1 for e in valid_events if e.get('status') == 'COMPLETED')
    if completed_count >= 3:
        score += 10
        feedback.append("All visits completed (+10)")
    elif completed_count > 0:
        score += 5
        feedback.append(f"{completed_count} visits completed (+5)")

    # 4. Check Dates and Data (20 pts Dates, 20 pts Data)
    date_score = 0
    data_score = 0
    
    # Tolerances
    def same_date(d1, d2):
        if not d1 or not d2: return False
        return d1[:10] == d2[:10] # Compare YYYY-MM-DD
    
    # Map found events to expected visits based on closest date match
    matched_visits = 0
    
    for expected in expected_visits:
        exp_date = expected['date']
        # Find closest event
        match = None
        for evt in valid_events:
            if same_date(evt.get('date'), exp_date):
                match = evt
                break
        
        if match:
            date_score += (20 / 3)
            matched_visits += 1
            
            # Check data values
            data_values = match.get('data_values') or []
            weight_found = False
            bp_found = False
            
            for dv in data_values:
                de_name = dv.get('data_element', '').lower()
                val = str(dv.get('value', ''))
                
                # Check Weight
                if 'weight' in de_name and val.startswith(expected['weight']):
                    weight_found = True
                
                # Check BP
                if ('systolic' in de_name or 'bp' in de_name) and val.startswith(expected['systolic']):
                    bp_found = True
            
            if weight_found: data_score += (10 / 3)
            if bp_found: data_score += (10 / 3)
            
    score += int(date_score)
    score += int(data_score)
    
    if date_score > 15: feedback.append("Visit dates match (+20)")
    else: feedback.append(f"Visit dates mismatch (Score: {int(date_score)})")
    
    if data_score > 15: feedback.append("Clinical data matches (+20)")
    else: feedback.append(f"Clinical data mismatch (Score: {int(data_score)})")

    return {
        "passed": score >= 70,
        "score": min(100, score),
        "feedback": "; ".join(feedback)
    }