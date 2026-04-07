#!/usr/bin/env python3
"""
Verifier for false_alarm_verification task.

This uses NORMAL footage - the correct answer is "no crime occurred".

Scores based on:
1. Report exists (15 pts)
2. Correctly identifies no crime (30 pts) - CRITICAL
3. Describes benign activity present (25 pts)
4. Gives correct verdict: DISMISS (20 pts)
5. Provides justification (10 pts)

Penalizes:
- Claiming criminal activity occurred (-30 pts from max)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_false_alarm_verification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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

    report_content = result.get('report_content', '')
    report_exists = result.get('report_exists', False)

    score = 0
    feedback = []

    # --- Criterion 1: Report exists (15 pts) ---
    if report_exists:
        score += 15
        feedback.append("Report created.")
    else:
        feedback.append("No report found.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    if not report_content or len(report_content) < 20:
        feedback.append("Report is empty or too short.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    content_lower = report_content.lower()

    # --- Criterion 2: Correctly identifies no crime (30 pts) ---
    # Check for FALSE POSITIVE indicators (agent correctly says nothing happened)
    no_crime_indicators = [
        'no suspicious', 'no criminal', 'no crime', 'nothing suspicious',
        'no incident', 'false alarm', 'no threat', 'no anomal',
        'normal activity', 'routine', 'nothing unusual', 'no evidence of',
        'does not appear', 'no signs of', 'benign',
    ]
    crime_claims = [
        'robbery', 'theft', 'assault', 'fight', 'attack', 'break-in',
        'burglary', 'vandalism', 'suspicious person', 'criminal activity detected',
    ]

    correctly_no_crime = any(ind in content_lower for ind in no_crime_indicators)
    falsely_claims_crime = any(
        claim in content_lower for claim in crime_claims
        if not any(neg in content_lower for neg in [f'no {claim}', f'not {claim}', f'no evidence of {claim}'])
    )

    if correctly_no_crime and not falsely_claims_crime:
        score += 30
        feedback.append("Correctly identifies no criminal activity.")
    elif falsely_claims_crime:
        # Major penalty for false positive
        feedback.append("INCORRECT: Falsely claims criminal activity in normal footage.")
    else:
        score += 10
        feedback.append("Ambiguous on whether crime occurred.")

    # --- Criterion 3: Describes activity present (25 pts) ---
    activity_words = [
        'vehicle', 'car', 'person', 'people', 'walking', 'moving',
        'pedestrian', 'traffic', 'activity', 'motion', 'movement',
        'passing', 'enter', 'exit', 'parked', 'drive', 'light',
    ]
    activity_described = sum(1 for w in activity_words if w in content_lower)

    if activity_described >= 4:
        score += 25
        feedback.append("Good description of benign activity.")
    elif activity_described >= 2:
        score += 15
        feedback.append("Some activity described.")
    elif activity_described >= 1:
        score += 5
        feedback.append("Minimal activity description.")
    else:
        feedback.append("No description of what triggered the alert.")

    # --- Criterion 4: Correct verdict (20 pts) ---
    if 'dismiss' in content_lower:
        score += 20
        feedback.append("Correct verdict: DISMISS.")
    elif 'false alarm' in content_lower:
        score += 20
        feedback.append("Correct verdict: false alarm.")
    elif 'escalate' in content_lower:
        feedback.append("INCORRECT verdict: ESCALATE on normal footage.")
    else:
        score += 5
        feedback.append("No clear DISMISS/ESCALATE verdict stated.")

    # --- Criterion 5: Justification (10 pts) ---
    if len(report_content) > 200:
        score += 10
        feedback.append("Detailed justification provided.")
    elif len(report_content) > 100:
        score += 5
        feedback.append("Brief justification.")

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }
