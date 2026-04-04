"""
Verifier for probation_caseload_triage task.

Scoring (100 pts total, threshold 70):
  - Priority escalation (30 pts): All 3 non-compliant cases have priority = 'High'
  - Compliant untouched (20 pts): None of the 4 compliant cases changed to 'High'
  - Notes added (25 pts): At least 3 notes with 'NON-COMPLIANCE FLAGGED' on non-compliant cases
  - Tasks created (25 pts): At least 3 tasks named 'Schedule immediate office report'
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)


def verify_probation_caseload_triage(traj, env_info, task_info):
    """
    Verify the probation caseload triage task.

    The agent must:
    1. Identify 3 non-compliant cases (Last Contact before Dec 1, 2025)
    2. Escalate each to priority 'High'
    3. Add a note containing 'NON-COMPLIANCE FLAGGED' to each
    4. Create a task 'Schedule immediate office report' for each
    Without modifying the 4 compliant cases.
    """
    copy_from_env = env_info.get("copy_from_env")
    metadata = task_info.get("metadata", {})

    result_path = "/tmp/probation_caseload_result.json"

    # Copy result file from environment VM
    if copy_from_env is None:
        logger.warning("copy_from_env not available; cannot verify")
        return {
            "score": 0,
            "passed": False,
            "feedback": "Verification infrastructure unavailable (copy_from_env missing)",
        }

    with tempfile.TemporaryDirectory() as tmpdir:
        local_path = os.path.join(tmpdir, "probation_caseload_result.json")
        try:
            copy_from_env(result_path, local_path)
        except Exception as e:
            logger.error("Failed to copy result file: %s", e)
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

    # --- Extract fields ---
    nc_high_count = data.get("nc_high_count", 0)
    c_wrongly_changed = data.get("c_wrongly_changed_count", 0)
    notes_count = data.get("noncompliant_notes_count", 0)
    tasks_count = data.get("tasks_count", 0)
    nc_priorities = data.get("nc_priorities", {})
    c_priorities = data.get("c_priorities", {})

    # --- Do-nothing / no-action gate ---
    # If nothing was done at all, return immediately with score=0
    if nc_high_count == 0 and notes_count == 0 and tasks_count == 0:
        return {
            "score": 0,
            "passed": False,
            "feedback": (
                "No actions detected. Non-compliant cases were not escalated, "
                "no notes were added, and no tasks were created."
            ),
            "details": {
                "nc_high_count": nc_high_count,
                "c_wrongly_changed": c_wrongly_changed,
                "notes_count": notes_count,
                "tasks_count": tasks_count,
            },
        }

    score = 0
    feedback_parts = []

    # --- Criterion 1: Priority escalation (30 pts) ---
    # Full credit: all 3 non-compliant cases escalated to High
    # Partial: 10 pts per case
    nc_pts_each = 10
    nc_pts = min(nc_high_count, 3) * nc_pts_each
    score += nc_pts
    feedback_parts.append(
        f"Priority escalation: {nc_high_count}/3 non-compliant cases set to 'High' "
        f"(+{nc_pts}/30 pts)"
    )
    if nc_high_count < 3:
        feedback_parts.append(
            f"  Non-compliant priorities: {nc_priorities}"
        )

    # --- Criterion 2: Compliant cases untouched (20 pts) ---
    # All-or-nothing: if any compliant case was wrongly changed, 0 pts for this criterion
    if c_wrongly_changed == 0:
        score += 20
        feedback_parts.append("Compliant cases untouched: all 4 compliant cases unmodified (+20/20 pts)")
    else:
        feedback_parts.append(
            f"Compliant cases modified: {c_wrongly_changed} compliant case(s) wrongly set to 'High' "
            f"(+0/20 pts). Compliant priorities: {c_priorities}"
        )

    # --- Criterion 3: Notes added to non-compliant cases (25 pts) ---
    # Full credit: at least 3 notes with 'NON-COMPLIANCE FLAGGED' on NC cases
    # Partial: ~8 pts per qualifying note
    note_pts_each = 8
    note_pts = min(notes_count, 3) * note_pts_each
    # Bonus 1 pt if exactly 3 (rounds to 25)
    if notes_count >= 3:
        note_pts = 25
    score += note_pts
    feedback_parts.append(
        f"Notes with 'NON-COMPLIANCE FLAGGED': {notes_count}/3 required notes found "
        f"(+{note_pts}/25 pts)"
    )

    # --- Criterion 4: Tasks created (25 pts) ---
    # Full credit: at least 3 tasks named 'Schedule immediate office report'
    # Partial: ~8 pts each
    task_pts_each = 8
    task_pts = min(tasks_count, 3) * task_pts_each
    if tasks_count >= 3:
        task_pts = 25
    score += task_pts
    feedback_parts.append(
        f"Tasks 'Schedule immediate office report': {tasks_count}/3 created "
        f"(+{task_pts}/25 pts)"
    )

    passed = score >= 70
    return {
        "score": score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "nc_high_count": nc_high_count,
            "c_wrongly_changed": c_wrongly_changed,
            "notes_count": notes_count,
            "tasks_count": tasks_count,
            "nc_priorities": nc_priorities,
            "c_priorities": c_priorities,
        },
    }
