"""
Verifier for hearing_schedule_conflict_resolution task.

Scoring (100 pts total, threshold 70):
  - Priority escalation (30 pts): All 3 overdue docket cases set to 'High'
  - Current cases untouched (20 pts): Neither of the 2 current dockets changed to 'High'
  - Continuance notes added (30 pts): At least 3 notes containing 'CONTINUANCE REQUIRED'
  - Status updated (20 pts): At least 2 of 3 overdue cases set to 'In Progress'
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_hearing_schedule_conflict_resolution(traj, env_info, task_info):
    """
    Verify the hearing schedule conflict resolution task.

    The agent must identify 3 overdue ALJ dockets (Hearing Date before Dec 30, 2025),
    escalate their priority to High, add a CONTINUANCE REQUIRED note, and set status
    to In Progress — without modifying the 2 current dockets.
    """
    copy_from_env = env_info.get("copy_from_env")

    if copy_from_env is None:
        return {
            "score": 0,
            "passed": False,
            "feedback": "Verification infrastructure unavailable (copy_from_env missing)",
        }

    result_path = "/tmp/hearing_conflict_result.json"

    with tempfile.TemporaryDirectory() as tmpdir:
        local_path = os.path.join(tmpdir, "hearing_conflict_result.json")
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

    od_high_count = data.get("od_high_count", 0)
    cur_wrongly_changed = data.get("cur_wrongly_changed_count", 0)
    notes_count = data.get("overdue_notes_count", 0)
    in_progress_count = data.get("od_in_progress_count", 0)

    # Do-nothing gate
    if od_high_count == 0 and notes_count == 0 and in_progress_count == 0:
        return {
            "score": 0,
            "passed": False,
            "feedback": (
                "No actions detected. Overdue dockets were not escalated, "
                "no continuance notes were added, and no statuses were updated."
            ),
        }

    score = 0
    feedback_parts = []

    # Criterion 1: Priority escalation (30 pts, 10 per case)
    pri_pts = min(od_high_count, 3) * 10
    score += pri_pts
    feedback_parts.append(
        f"Priority escalation: {od_high_count}/3 overdue dockets set to 'High' (+{pri_pts}/30 pts)"
    )

    # Criterion 2: Current cases untouched (20 pts, all-or-nothing)
    if cur_wrongly_changed == 0:
        score += 20
        feedback_parts.append("Current cases untouched: both current dockets unmodified (+20/20 pts)")
    else:
        feedback_parts.append(
            f"Current cases modified: {cur_wrongly_changed} current docket(s) wrongly changed (+0/20 pts)"
        )

    # Criterion 3: Continuance notes (30 pts)
    if notes_count >= 3:
        note_pts = 30
    else:
        note_pts = min(notes_count, 3) * 10
    score += note_pts
    feedback_parts.append(
        f"Continuance notes: {notes_count}/3 'CONTINUANCE REQUIRED' notes found (+{note_pts}/30 pts)"
    )

    # Criterion 4: Status updated to In Progress (20 pts)
    # Full credit for 3, partial for 2, 0 for 0-1
    if in_progress_count >= 3:
        status_pts = 20
    elif in_progress_count == 2:
        status_pts = 13
    elif in_progress_count == 1:
        status_pts = 7
    else:
        status_pts = 0
    score += status_pts
    feedback_parts.append(
        f"Status 'In Progress': {in_progress_count}/3 overdue cases updated (+{status_pts}/20 pts)"
    )

    passed = score >= 70
    return {
        "score": score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "od_high_count": od_high_count,
            "cur_wrongly_changed": cur_wrongly_changed,
            "notes_count": notes_count,
            "in_progress_count": in_progress_count,
        },
    }
