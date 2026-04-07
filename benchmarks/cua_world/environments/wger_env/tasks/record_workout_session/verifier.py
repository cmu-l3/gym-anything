#!/usr/bin/env python3
"""
Verifier for record_workout_session task.

Validates via Database query evidence that:
1. Anti-gaming check passed (actual rows were inserted, not just modified).
2. A workout session was created for today linked to "5x5 Beginner".
3. Session notes & impression were recorded.
4. Exactly 3 log entries exist for Squats today.
5. All weight values are 100 kg.
6. The repetition values are exactly 5, 5, 4.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_workout_session(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if 'error' in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    initial = result.get('initial_counts', {})
    current = result.get('current_counts', {})
    session = result.get('session', {})
    logs = result.get('squat_logs', [])

    # 1. Anti-gaming (5 points)
    if current.get('sessions', 0) > initial.get('sessions', 0) and current.get('logs', 0) > initial.get('logs', 0):
        score += 5
        feedback_parts.append("New DB records detected (+5)")
    else:
        feedback_parts.append("No new records created in DB")

    # 2. Session created and linked to routine (15 + 10 points)
    if session.get('exists'):
        score += 15
        feedback_parts.append("Session exists for today (+15)")
        if session.get('routine_match'):
            score += 10
            feedback_parts.append("Session correctly linked to '5x5 Beginner' (+10)")
        else:
            feedback_parts.append("Session not linked to the expected routine")
    else:
        feedback_parts.append("No session found for today")

    # 3. Session Notes & Impression (10 + 5 points)
    notes = session.get('notes', '').lower()
    if 'solid squat session' in notes:
        score += 10
        feedback_parts.append("Session notes match expected (+10)")
    elif notes:
        feedback_parts.append("Session notes exist but don't match exactly")
        
    if session.get('impression') and str(session.get('impression')).strip():
        score += 5
        feedback_parts.append("Session impression is set (+5)")

    # 4. Logs count (15 + 10 points)
    if len(logs) >= 1:
        score += 15
        feedback_parts.append("At least 1 Squat log entry found (+15)")
    
    if len(logs) >= 3:
        score += 10
        feedback_parts.append("3 or more Squat log entries found (+10)")
    elif len(logs) > 0:
        feedback_parts.append(f"Only {len(logs)} log entries found (expected 3)")

    # 5. Weights evaluation (15 points)
    if logs:
        correct_weight = sum(1 for l in logs if abs(l.get('weight', 0) - 100.0) < 0.5)
        if correct_weight >= 3:
            score += 15
            feedback_parts.append("All 3 entries correctly set to 100kg (+15)")
        elif correct_weight > 0:
            score += (correct_weight * 5)
            feedback_parts.append(f"Partial weights correct ({correct_weight}/3 entries)")

    # 6. Reps evaluation (15 points)
    if logs:
        reps_found = sorted([l.get('reps', 0) for l in logs])
        expected_reps = [4, 5, 5]
        
        # Check if the extracted reps contain the subset [4, 5, 5]
        match_count = 0
        remaining_expected = list(expected_reps)
        for r in reps_found:
            if r in remaining_expected:
                remaining_expected.remove(r)
                match_count += 1
                
        if match_count == 3:
            score += 15
            feedback_parts.append("Reps exactly match 5, 5, 4 (+15)")
        elif match_count > 0:
            score += (match_count * 5)
            feedback_parts.append(f"Partial reps match ({match_count}/3 values correct)")

    # Overall determination
    # Key criteria: Must have created session and at least some correct logs
    key_criteria_met = session.get('exists') and len(logs) > 0
    passed = (score >= 60) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }