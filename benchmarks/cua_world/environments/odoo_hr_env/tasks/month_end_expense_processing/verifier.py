#!/usr/bin/env python3
"""Verifier for month_end_expense_processing task.

Multi-criterion scoring (100 pts total, pass >= 60):

  C1 (25 pts): Anita Oliver has an expense report that is submitted or beyond
               (state in: submit, approve, post, done).

  C2 (25 pts): Sharlene Rhodes has an expense report that is submitted or beyond.

  C3 (50 pts): Paul Williams has an expense report that is APPROVED or beyond
               (state in: approve, post, done).
               Partial (20 pts): Paul Williams's report exists but is only submitted.

Partial max: 0 + 0 + 20 = 20 < 60 (pass threshold). Safe against antipattern 4.
C1 + C2 alone = 50 < 60, so agent cannot pass without at least partially completing C3.
"""

import json
import os
import tempfile


def verify_expense_processing(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/expense_processing_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    # C1: Anita Oliver submitted
    anita = result.get("anita_oliver", {})
    if anita.get("submitted"):
        score += 25
        feedback_parts.append(f"Anita Oliver expense report submitted (state={anita.get('state')}) (+25)")
    else:
        state_str = anita.get("state") or "no report"
        feedback_parts.append(f"Anita Oliver report not submitted (state={state_str}) (+0)")

    # C2: Sharlene Rhodes submitted
    sharlene = result.get("sharlene_rhodes", {})
    if sharlene.get("submitted"):
        score += 25
        feedback_parts.append(f"Sharlene Rhodes expense report submitted (state={sharlene.get('state')}) (+25)")
    else:
        state_str = sharlene.get("state") or "no report"
        feedback_parts.append(f"Sharlene Rhodes report not submitted (state={state_str}) (+0)")

    # C3: Paul Williams approved
    paul = result.get("paul_williams", {})
    if paul.get("approved"):
        score += 50
        feedback_parts.append(f"Paul Williams expense report approved (state={paul.get('state')}) (+50)")
    elif paul.get("submitted"):
        score += 20
        feedback_parts.append(f"Paul Williams report submitted but not approved (state={paul.get('state')}) (+20 partial)")
    else:
        state_str = paul.get("state") or "no report"
        feedback_parts.append(f"Paul Williams report not submitted (state={state_str}) (+0)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
