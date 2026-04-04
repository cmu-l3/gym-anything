#!/usr/bin/env python3
"""
Verifier for customer_dispute_resolution task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  25 pts  Credit note for Alfreds ~$600
  25 pts  Credit note for Alfreds ~$60
  25 pts  Ernst receipt $450 allocated (INV-E002 cleared)
  25 pts  At least 2 new credit notes created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_customer_dispute_resolution(traj, env_info, task_info):
    """Verify customer dispute resolution task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/customer_dispute_resolution_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export_result.sh may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    score = 0
    criteria = {}
    new_cn = result.get("new_credit_note_count", 0)

    # Criterion 1: Credit note for Alfreds ~$600 (25 pts)
    c1 = result.get("has_alfreds_credit_note_600", False) and new_cn > 0
    if c1:
        score += 25
    criteria["credit_note_alfreds_600"] = {"passed": c1, "points": 25 if c1 else 0, "max_points": 25}

    # Criterion 2: Credit note for Alfreds ~$60 (25 pts)
    c2 = result.get("has_alfreds_credit_note_60", False) and new_cn >= 2
    if c2:
        score += 25
    criteria["credit_note_alfreds_60"] = {"passed": c2, "points": 25 if c2 else 0, "max_points": 25}

    # Criterion 3: Ernst receipt allocated — INV-E002 cleared (25 pts)
    # Requires INV-E002 to show 0.00 balance (allocated receipt reduces outstanding to zero)
    c3 = result.get("inv_e002_cleared", False)
    if c3:
        score += 25
    criteria["ernst_receipt_allocated"] = {
        "passed": c3, "points": 25 if c3 else 0, "max_points": 25,
        "details": {"inv_e002_cleared": result.get("inv_e002_cleared"),
                    "receipt_exists": result.get("ernst_receipt_450_exists")}
    }

    # Criterion 4: At least 2 new credit notes (25 pts)
    c4 = new_cn >= 2
    if c4:
        score += 25
    criteria["two_credit_notes_created"] = {
        "passed": c4, "points": 25 if c4 else 0, "max_points": 25,
        "details": {"new_credit_note_count": new_cn}
    }

    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        feedback_parts.append(f"  [{'PASS' if c['passed'] else 'FAIL'}] {name}: {c['points']}/{c['max_points']} pts")
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts), "criteria": criteria}
