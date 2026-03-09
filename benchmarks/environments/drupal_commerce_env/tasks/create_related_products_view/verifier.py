#!/usr/bin/env python3
"""Verifier for create_related_products_view."""

import json
import os
import tempfile


def verify_create_related_products_view(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/create_related_products_view_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as exc:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {exc}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = int(result.get("score", 0))
    criteria = result.get("criteria", [])
    passed = score >= 60
    feedback = "; ".join(
        f"{item.get('name')}: {'ok' if item.get('passed') else 'fail'}"
        for item in criteria
    ) or "No criteria returned"

    return {"passed": passed, "score": score, "feedback": feedback}
