#!/usr/bin/env python3
"""
Verifier for journal_period_close task.

Reads the JSON exported by export_result.sh via copy_from_env.

Scoring (100 points, pass >= 65):
  30 pts  JE-1: $450 depreciation balanced
  30 pts  JE-2: $300 insurance balanced
  30 pts  JE-3: $2,400 wages balanced
  10 pts  JE count increased by >= 3
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_journal_period_close(traj, env_info, task_info):
    """Verify journal period close task completion."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/journal_period_close_result.json", tmp.name)
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

    c1 = result.get("je_depreciation_ok", False)
    if c1:
        score += 30
    criteria["je_depreciation_450"] = {
        "passed": c1, "points": 30 if c1 else 0, "max_points": 30,
        "details": {"in_list": result.get("je_450_in_list"), "balanced": result.get("je_450_balanced")}
    }

    c2 = result.get("je_insurance_ok", False)
    if c2:
        score += 30
    criteria["je_insurance_300"] = {
        "passed": c2, "points": 30 if c2 else 0, "max_points": 30,
        "details": {"in_list": result.get("je_300_in_list"), "balanced": result.get("je_300_balanced")}
    }

    c3 = result.get("je_wages_ok", False)
    if c3:
        score += 30
    criteria["je_wages_2400"] = {
        "passed": c3, "points": 30 if c3 else 0, "max_points": 30,
        "details": {"in_list": result.get("je_2400_in_list"), "balanced": result.get("je_2400_balanced")}
    }

    c4 = result.get("je_count_increased_3", False)
    if c4:
        score += 10
    criteria["je_count_3_plus"] = {
        "passed": c4, "points": 10 if c4 else 0, "max_points": 10,
        "details": {"new_je_count": result.get("new_je_count"),
                    "baseline": result.get("baseline_je"), "current": result.get("current_je_count")}
    }

    passed = score >= 65
    feedback_parts = [f"Score: {score}/100"]
    for name, c in criteria.items():
        feedback_parts.append(f"  [{'PASS' if c['passed'] else 'FAIL'}] {name}: {c['points']}/{c['max_points']} pts")
    return {"passed": passed, "score": score, "feedback": "\n".join(feedback_parts), "criteria": criteria}
