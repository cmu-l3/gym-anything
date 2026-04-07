#!/usr/bin/env python3
"""Verifier for times_table_memory_game task.

Checks that the agent created a Memorize memory card game with 6x table pairs,
saved to the Sugar Journal as '6 Times Table Game'.
"""

import json
import os
import tempfile


def verify_times_table_memory_game(traj, env_info, task_info):
    """Verify the 6 times table memory game was created correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/times_table_memory_game_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Journal entry titled '6 Times Table Game' exists (30 pts)
    if result.get('journal_found'):
        score += 30
        feedback.append("Journal entry '6 Times Table Game' found")
    else:
        feedback.append("FAIL: Journal entry '6 Times Table Game' not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Game data file has content (10 pts)
    data_size = result.get('data_size', 0)
    if data_size > 100:
        score += 10
        feedback.append(f"Game data file has content ({data_size} bytes)")
    else:
        feedback.append(f"Game data very small ({data_size} bytes) — may be empty")

    # Criterion 3: Game contains 6x table expressions (25 pts)
    if result.get('has_six_table'):
        score += 25
        feedback.append("6x table expressions found in game data")
    else:
        feedback.append("No 6x table expressions detected in game data")

    # Criterion 4: Game has the lowest answer (6 = 6x1) (15 pts)
    if result.get('has_answer_6'):
        score += 15
        feedback.append("Answer '6' (6x1) present")
    else:
        feedback.append("Missing answer '6' (6x1)")

    # Criterion 5: Game has the highest answer (48 = 6x8) (20 pts)
    if result.get('has_answer_48'):
        score += 20
        feedback.append("Answer '48' (6x8) present — full range covered")
    else:
        feedback.append("Missing answer '48' (6x8) — may not have all 8 pairs")

    # Pass: score >= 60 AND journal found AND has 6x table content
    passed = (score >= 60 and
              result.get('journal_found', False) and
              result.get('has_six_table', False))

    if passed:
        pair_count = result.get('pair_count', 0)
        feedback.append(f"Memory game complete! ({pair_count} pairs detected)")
    else:
        reasons = []
        if not result.get('journal_found'):
            reasons.append("game not saved to Journal")
        if not result.get('has_six_table'):
            reasons.append("no 6x table content found")
        if score < 60:
            reasons.append(f"score {score} < 60")
        feedback.append(f"FAILED: {'; '.join(reasons)}")

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "subscores": {
            "journal_found": result.get('journal_found', False),
            "has_six_table": result.get('has_six_table', False),
            "pair_count": result.get('pair_count', 0),
            "data_size": result.get('data_size', 0)
        }
    }
