#!/usr/bin/env python3
"""Verifier for supplier_capa_closure task.

Multi-criterion scoring (100 pts total, pass >= 60):
  C1 (35 pts): All In Progress alerts have non-empty corrective_action
               Partial: 17 pts if >=50% have corrective_action
  C2 (35 pts): All In Progress alerts have non-empty preventive_action
               Partial: 17 pts if >=50% have preventive_action
  C3 (30 pts): All In Progress alerts transitioned to Done stage
               Partial: 15 pts if >=50% are in Done stage
"""

import json
import os
import tempfile


def verify_supplier_capa_closure(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    copy_from_env = env_info.get("copy_from_env") if env_info else None
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env("/tmp/supplier_capa_closure_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        os.unlink(tmp.name)

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    alerts = result.get("alerts", [])
    total = result.get("total_target_alerts", len(alerts))
    done_stage_id = result.get("done_stage_id")

    if total == 0:
        return {"passed": False, "score": 0, "feedback": "No target alerts found in result (setup failure)"}

    def is_done(alert):
        sid = alert.get("stage_id")
        sname = (alert.get("stage_name") or "").lower()
        if done_stage_id and sid == done_stage_id:
            return True
        return "done" in sname or "close" in sname

    # C1: Corrective actions present (>=10 chars = substantive)
    ca_count = sum(1 for a in alerts if len(a.get("corrective_action", "")) >= 10)
    if ca_count == total:
        score += 35
        feedback_parts.append(f"All {total} alerts have corrective_action (+35)")
    elif ca_count >= max(1, (total + 1) // 2):
        score += 17
        feedback_parts.append(f"{ca_count}/{total} alerts have corrective_action, partial (+17)")
    else:
        feedback_parts.append(f"Only {ca_count}/{total} alerts have corrective_action")

    # C2: Preventive actions present
    pa_count = sum(1 for a in alerts if len(a.get("preventive_action", "")) >= 10)
    if pa_count == total:
        score += 35
        feedback_parts.append(f"All {total} alerts have preventive_action (+35)")
    elif pa_count >= max(1, (total + 1) // 2):
        score += 17
        feedback_parts.append(f"{pa_count}/{total} alerts have preventive_action, partial (+17)")
    else:
        feedback_parts.append(f"Only {pa_count}/{total} alerts have preventive_action")

    # C3: All transitioned to Done stage
    done_count = sum(1 for a in alerts if is_done(a))
    if done_count == total:
        score += 30
        feedback_parts.append(f"All {total} alerts transitioned to Done (+30)")
    elif done_count >= max(1, (total + 1) // 2):
        score += 15
        feedback_parts.append(f"{done_count}/{total} alerts in Done stage, partial (+15)")
    else:
        feedback_parts.append(f"Only {done_count}/{total} alerts in Done stage")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts),
    }
