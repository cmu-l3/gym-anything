#!/usr/bin/env python3
"""
Verifier for overdue_followup_scheduling task.

The agent must:
1. Identify which patients in the database have not had a consultation in > 6 months
2. Schedule follow-up appointments for each overdue patient
3. NOT schedule appointments for patients who already have recent consultations

Five overdue patients: PETIT Nathalie, DURAND Christophe, GIRARD Michel, MOREL Sylvie, HENRY Emmanuel
Two NOT overdue: ROUX Celine, BLANC David

Scoring (100 points):
  - PETIT Nathalie appointment scheduled:  20 pts
  - DURAND Christophe appointment scheduled: 20 pts
  - GIRARD Michel appointment scheduled:  20 pts
  - MOREL Sylvie appointment scheduled:   20 pts
  - HENRY Emmanuel appointment scheduled: 20 pts
  Penalty: -10 pts for each non-overdue patient incorrectly scheduled (ROUX or BLANC)

Pass threshold: 60 points (must schedule at least 3 of 5 overdue patients)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_overdue_followup_scheduling(traj, env_info, task_info):
    """Verify that overdue patients were identified and scheduled."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env("/tmp/overdue_followup_result.json", tmp_path)
            with open(tmp_path, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback_parts = []
    details = {}

    # Each correctly scheduled overdue patient: 20 pts
    overdue_patients = [
        ('petit', 'PETIT Nathalie'),
        ('durand', 'DURAND Christophe'),
        ('girard', 'GIRARD Michel'),
        ('morel', 'MOREL Sylvie'),
        ('henry', 'HENRY Emmanuel'),
    ]

    scheduled_count = 0
    for key, name in overdue_patients:
        val = int(result.get(f'{key}_scheduled', 0))
        if val > 0:
            score += 20
            scheduled_count += 1
            feedback_parts.append(f"{name}: appointment scheduled (+20)")
            details[f'{key}_scheduled'] = True
        else:
            feedback_parts.append(f"{name}: not scheduled (0)")
            details[f'{key}_scheduled'] = False

    # Penalty for scheduling non-overdue patients
    roux_wrong = int(result.get('roux_scheduled_incorrectly', 0))
    blanc_wrong = int(result.get('blanc_scheduled_incorrectly', 0))

    if roux_wrong > 0:
        penalty = min(10, score)
        score -= penalty
        feedback_parts.append(f"ROUX Celine incorrectly scheduled (recent consultation!) (-{penalty})")
        details['roux_penalty'] = penalty

    if blanc_wrong > 0:
        penalty = min(10, score)
        score -= penalty
        feedback_parts.append(f"BLANC David incorrectly scheduled (recent consultation!) (-{penalty})")
        details['blanc_penalty'] = penalty

    score = max(0, score)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) or "No overdue patients scheduled",
        "details": {
            "overdue_patients_scheduled": scheduled_count,
            **details,
        }
    }
