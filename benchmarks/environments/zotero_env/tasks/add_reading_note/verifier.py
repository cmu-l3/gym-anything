#!/usr/bin/env python3
"""
Verifier for add_reading_note task.

Task: Add a child note to "Attention Is All You Need" containing
      'Transformer', 'self-attention', and 'translation'.

Scoring (100 points):
  - Note exists as child of the correct paper:  30 pts
  - Note contains 'Transformer':                25 pts
  - Note contains 'self-attention':             25 pts
  - Note contains 'translation':                10 pts
  - Note has substantial content (>=100 chars): 10 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_add_reading_note(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/add_reading_note_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: Note attached to correct paper (30 pts)
    note_found = result.get("note_found", False)
    if note_found:
        score += 30
        subscores["note_attached"] = True
        feedback_parts.append("Note attached to 'Attention Is All You Need'")
    else:
        subscores["note_attached"] = False
        # If no note on target paper, check if notes_attached > 0 at all
        if result.get("target_paper_id", 0) == 0:
            feedback_parts.append("Target paper not found in DB")
        else:
            feedback_parts.append("No note found attached to 'Attention Is All You Need'")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # Criterion 2: Contains 'Transformer' (25 pts)
    if result.get("has_transformer", False):
        score += 25
        subscores["has_transformer"] = True
        feedback_parts.append("Contains 'Transformer'")
    else:
        subscores["has_transformer"] = False
        feedback_parts.append("Missing 'Transformer'")

    # Criterion 3: Contains 'self-attention' (25 pts)
    if result.get("has_self_attention", False):
        score += 25
        subscores["has_self_attention"] = True
        feedback_parts.append("Contains 'self-attention'")
    else:
        subscores["has_self_attention"] = False
        feedback_parts.append("Missing 'self-attention'")

    # Criterion 4: Contains 'translation' (10 pts)
    if result.get("has_translation", False):
        score += 10
        subscores["has_translation"] = True
        feedback_parts.append("Contains 'translation'")
    else:
        subscores["has_translation"] = False
        feedback_parts.append("Missing 'translation'")

    # Criterion 5: Substantial note (10 pts)
    note_len = result.get("note_length", 0)
    if note_len >= 100:
        score += 10
        subscores["substantial_note"] = True
        feedback_parts.append(f"Note has {note_len} chars (substantial)")
    else:
        subscores["substantial_note"] = False
        feedback_parts.append(f"Note too short ({note_len} chars, need 100+)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
