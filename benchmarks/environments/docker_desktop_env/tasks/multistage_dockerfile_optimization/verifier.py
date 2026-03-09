#!/usr/bin/env python3
"""Verifier for multistage_dockerfile_optimization task.

Scoring (100 points):
- Multi-stage Dockerfile (20 pts): Dockerfile has >= 2 FROM statements
- Optimized image exists (15 pts): todo-app:optimized tag present
- Image size < 250 MB (30 pts): full credit <250MB; 10pts 250-400MB; 0 if >400MB
- Size reduction >= 50% (20 pts): optimized is less than half the original size
- App functional (15 pts): running optimized container serves HTTP 200

Pass threshold: 70 points
Mandatory: multi-stage + optimized image + size < 250MB
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_multistage_dockerfile_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/multistage_dockerfile_optimization_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {e}"}

    score = 0
    feedback_parts = []
    details = {}

    is_multistage = result.get("is_multistage", False)
    from_count = result.get("from_count", 0)
    optimized_exists = result.get("optimized_image_exists", False)
    optimized_mb = result.get("optimized_size_mb", 0)
    original_mb = result.get("original_size_mb", 0)
    http_code = result.get("app_http_code", "000")

    # Criterion 1: Multi-stage Dockerfile (20 pts)
    if is_multistage:
        score += 20
        feedback_parts.append(f"Multi-stage Dockerfile ({from_count} FROM stages) (+20)")
    else:
        feedback_parts.append(f"Single-stage Dockerfile ({from_count} FROM) — must use multi-stage (+0)")
    details["is_multistage"] = is_multistage

    # Criterion 2: Optimized image exists (15 pts)
    if optimized_exists:
        score += 15
        feedback_parts.append("todo-app:optimized image exists (+15)")
    else:
        feedback_parts.append("todo-app:optimized not found — must build with that tag (+0)")
    details["optimized_exists"] = optimized_exists

    # Criterion 3: Image size threshold (30 pts)
    if optimized_exists:
        if optimized_mb < 250:
            score += 30
            feedback_parts.append(f"Image size {optimized_mb}MB < 250MB (+30)")
        elif optimized_mb < 400:
            score += 10
            feedback_parts.append(f"Image size {optimized_mb}MB — under 400MB but above 250MB target (+10)")
        else:
            feedback_parts.append(f"Image size {optimized_mb}MB — exceeds 400MB, insufficient optimization (+0)")
    else:
        feedback_parts.append("Cannot check size — image not built (+0)")
    details["optimized_size_mb"] = optimized_mb

    # Criterion 4: Size reduction >= 50% (20 pts)
    if optimized_exists and original_mb > 0:
        reduction_pct = (original_mb - optimized_mb) / original_mb * 100
        if reduction_pct >= 50:
            score += 20
            feedback_parts.append(f"Size reduced by {reduction_pct:.0f}% ({original_mb}MB -> {optimized_mb}MB) (+20)")
        elif reduction_pct >= 25:
            score += 10
            feedback_parts.append(f"Size reduced by {reduction_pct:.0f}% — improvement but below 50% target (+10)")
        else:
            feedback_parts.append(f"Size only reduced by {reduction_pct:.0f}% — insufficient (+0)")
        details["reduction_pct"] = round(reduction_pct, 1)
    else:
        feedback_parts.append("Cannot measure size reduction (+0)")

    # Criterion 5: App functional (15 pts)
    if http_code in ("200", "301", "302"):
        score += 15
        feedback_parts.append(f"App responds HTTP {http_code} (+15)")
    else:
        feedback_parts.append(f"App not responding (HTTP {http_code}) (+0)")
    details["app_http_code"] = http_code

    # Pass requires multi-stage + image exists + size < 250MB + score >= 70
    passed = is_multistage and optimized_exists and optimized_mb < 250 and score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
