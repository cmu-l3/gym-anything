#!/usr/bin/env python3
"""
Verifier for stolen_card_replacement task.

Affected users (setup assigns them compromised cards):
  • Heather Morrison — card 0004521820
  • Robert Nakamura  — card 0004521821

Required actions per user:
  1. Remove the compromised card (0004521820x series)
  2. Assign a replacement card in range 0004522100–0004522109

Scoring (100 pts total, pass threshold = 70):

  Per affected user (each is worth 50 pts total):
    • Compromised card removed:      20 pts
    • Replacement card assigned:     30 pts

  max_partial_total analysis:
    Do-nothing (compromised cards still present): 0 pts → FAIL ✓
    Both compromised removed, no replacements: 40 < 70 ✓
    One user fully fixed (50) + other's compromised removed (20): 70 → PASS ✓ (reasonable)
    One user fully fixed (50) + other untouched (0): 50 < 70 ✓
    Both users fully fixed: 100 ✓
"""

import json
import os
import tempfile

COMPROMISED_CARDS = {
    "0004521820", "0004521821", "0004521822", "0004521823", "0004521824",
    "0004521825", "0004521826", "0004521827", "0004521828", "0004521829",
}
REPLACEMENT_START = 4522100
REPLACEMENT_END   = 4522109

TARGETS = ["Heather Morrison", "Robert Nakamura"]


def _has_replacement(card_numbers):
    for cn in card_numbers:
        if cn.isdigit() and REPLACEMENT_START <= int(cn) <= REPLACEMENT_END:
            return True
    return False


def verify_stolen_card_replacement(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "copy_from_env not available in env_info"}

    tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/stolen_card_replacement_result.json", tmp)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not retrieve result file: {e}"}

    try:
        with open(tmp) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not parse result JSON: {e}"}
    finally:
        try:
            os.remove(tmp)
        except Exception:
            pass

    score = 0
    feedback = []
    user_results = result.get("user_results", {})

    for name in TARGETS:
        info = user_results.get(name)
        if not info:
            feedback.append(f"FAIL: {name} — user not found in export results")
            continue

        cards = info.get("card_numbers", [])

        # Compromised card removed
        has_comp = info.get("has_compromised_card", True)
        if not has_comp:
            score += 20
            feedback.append(f"PASS: {name} — compromised card removed (+20)")
        else:
            comp_found = [c for c in cards if c in COMPROMISED_CARDS]
            feedback.append(
                f"FAIL: {name} — still has compromised card(s): {comp_found}"
            )

        # Replacement card assigned
        has_repl = _has_replacement(cards)
        if has_repl:
            repl = [c for c in cards if c.isdigit()
                    and REPLACEMENT_START <= int(c) <= REPLACEMENT_END]
            score += 30
            feedback.append(
                f"PASS: {name} — replacement card assigned: {repl} (+30)"
            )
        else:
            feedback.append(
                f"FAIL: {name} — no replacement card in range "
                f"0004522100–0004522109 (current cards: {cards})"
            )

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
    }
