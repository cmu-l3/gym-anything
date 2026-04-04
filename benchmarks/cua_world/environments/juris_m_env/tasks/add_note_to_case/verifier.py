#!/usr/bin/env python3
"""
Verifier for add_note_to_case task.

Verification strategy:
1. Read exported JSON from VM via copy_from_env
2. Check that at least 1 note was added to a library item
3. Preferably check that the note is attached to Brown v. Board

Scoring (100 points):
- At least 1 note exists in the library: 40 pts
- Note is attached to a parent item (not standalone): 30 pts
- Note is attached to Brown v. Board specifically: +20 pts
- Note has non-trivial content (length > 20 chars): 10 pts

Pass threshold: 40 points (any note was added)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_add_note_to_case(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that a note was added to a case in the library."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_note_to_case_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []

    note_count = result.get("note_count", 0)
    notes_with_parent = result.get("notes_with_parent", 0)
    notes_on_brown = result.get("notes_on_brown_v_board", 0)
    content_len = result.get("note_content_length", 0)

    logger.info(
        f"note_count={note_count}, with_parent={notes_with_parent}, "
        f"on_brown={notes_on_brown}, content_len={content_len}"
    )

    # Note exists
    if note_count > 0:
        score += 40
        feedback.append(f"{note_count} note(s) found in library (+40)")
    else:
        feedback.append(
            "No notes found. Select 'Brown v. Board of Education', click the 'Notes' tab "
            "in the right panel, and click 'Add' to add a note."
        )
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback), "details": result}

    # Note attached to a parent item
    if notes_with_parent > 0:
        score += 30
        feedback.append("Note is attached to a library item (+30)")
    else:
        feedback.append("Note is not attached to any item (standalone note)")

    # Note on Brown v. Board specifically
    if notes_on_brown > 0:
        score += 20
        feedback.append("Note attached to Brown v. Board of Education (+20)")
    else:
        feedback.append("Note not found on Brown v. Board (may be on another item — partial credit)")

    # Non-trivial content
    if content_len > 20:
        score += 10
        feedback.append(f"Note has {content_len} chars of content (+10)")
    else:
        feedback.append(f"Note content is very short ({content_len} chars)")

    passed = score >= 40
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result,
    }
