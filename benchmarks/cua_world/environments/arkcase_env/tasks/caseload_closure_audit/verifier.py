"""
Verifier for caseload_closure_audit task.

Scoring (100 pts total, threshold 70):
  - Expired cases closed (40 pts): All 3 expired supervision cases have status = 'Closed'
    (partial: 13 pts per case closed, 1 bonus pt at full completion)
  - Active cases untouched (20 pts): None of the 3 active cases changed to 'Closed'
  - Closure notes added (40 pts): At least 3 unique expired cases have a note containing
    'CASE CLOSED' and 'SOP-PO-12'
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_caseload_closure_audit(traj, env_info, task_info):
    """
    Verify the caseload closure audit task.

    The agent must identify 3 expired supervision cases (Supervision End Date before Jan 1, 2026),
    close their status, and add a CASE CLOSED note — without modifying the 3 active cases.
    """
    copy_from_env = env_info.get("copy_from_env")

    if copy_from_env is None:
        return {
            "score": 0,
            "passed": False,
            "feedback": "Verification infrastructure unavailable (copy_from_env missing)",
        }

    result_path = "/tmp/closure_audit_result.json"

    with tempfile.TemporaryDirectory() as tmpdir:
        local_path = os.path.join(tmpdir, "closure_audit_result.json")
        try:
            copy_from_env(result_path, local_path)
        except Exception as e:
            return {
                "score": 0,
                "passed": False,
                "feedback": f"Could not copy result file from VM: {e}",
            }

        try:
            with open(local_path) as f:
                data = json.load(f)
        except Exception as e:
            return {
                "score": 0,
                "passed": False,
                "feedback": f"Result file could not be parsed: {e}",
            }

    exp_closed_count = data.get("exp_closed_count", 0)
    act_wrongly_closed = data.get("act_wrongly_closed_count", 0)
    cases_with_notes = data.get("cases_with_closure_notes", 0)

    # Do-nothing gate
    if exp_closed_count == 0 and cases_with_notes == 0:
        return {
            "score": 0,
            "passed": False,
            "feedback": (
                "No actions detected. No expired cases were closed and no closure notes were added."
            ),
            "details": {
                "exp_closed_count": exp_closed_count,
                "act_wrongly_closed": act_wrongly_closed,
                "cases_with_notes": cases_with_notes,
            },
        }

    score = 0
    feedback_parts = []

    # Criterion 1: Expired cases closed (40 pts, 13 each + 1 bonus)
    if exp_closed_count >= 3:
        closed_pts = 40
    else:
        closed_pts = min(exp_closed_count, 3) * 13
    score += closed_pts
    feedback_parts.append(
        f"Expired cases closed: {exp_closed_count}/3 set to 'Closed' (+{closed_pts}/40 pts)"
    )
    if exp_closed_count < 3:
        exp_statuses = data.get("exp_statuses", {})
        feedback_parts.append(f"  Expired case statuses: {exp_statuses}")

    # Criterion 2: Active cases untouched (20 pts, all-or-nothing)
    if act_wrongly_closed == 0:
        score += 20
        feedback_parts.append("Active cases untouched: all 3 active cases unchanged (+20/20 pts)")
    else:
        feedback_parts.append(
            f"Active cases incorrectly closed: {act_wrongly_closed} active case(s) set to 'Closed' (+0/20 pts)"
        )

    # Criterion 3: Closure notes added (40 pts, ~13 per unique case)
    if cases_with_notes >= 3:
        note_pts = 40
    else:
        note_pts = min(cases_with_notes, 3) * 13
    score += note_pts
    feedback_parts.append(
        f"Closure notes: {cases_with_notes}/3 expired cases have 'CASE CLOSED' + 'SOP-PO-12' note (+{note_pts}/40 pts)"
    )

    passed = score >= 70
    return {
        "score": score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "exp_closed_count": exp_closed_count,
            "act_wrongly_closed": act_wrongly_closed,
            "cases_with_notes": cases_with_notes,
            "exp_statuses": data.get("exp_statuses", {}),
            "act_statuses": data.get("act_statuses", {}),
        },
    }
