#!/usr/bin/env python3
"""Verifier for cps_wage_diagnostics task.

Agent must run log-wage OLS regression followed by RESET, Breusch-Pagan,
and White heteroskedasticity tests on the CPS wage dataset.

Scoring (100 points):
- File exists and was created after task start: 15 points
- OLS regression results present: 15 points
- RESET specification test present: 20 points
- Breusch-Pagan heteroskedasticity test present: 20 points
- White heteroskedasticity test present: 20 points
- File substantiality (>4KB for 4 test outputs): 10 points

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cps_wage_diagnostics(traj, env_info, task_info):
    """Verify OLS + diagnostic tests on CPS wage data."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/Documents/gretl_output/wage_diagnostics.txt')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/cps_wage_diagnostics_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- Check 1: File exists and is new (15 pts) ----
    file_exists = result.get('file_exists', False)
    created_after = result.get('file_created_after_start', False)

    if file_exists and created_after:
        score += 15
        subscores['file_new'] = True
        feedback_parts.append("Output file created during task")
    elif file_exists:
        score += 5
        subscores['file_new'] = False
        feedback_parts.append("Output file exists but predates task start")
    else:
        subscores['file_new'] = False
        feedback_parts.append(f"Output file not found at {expected_output}")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ---- Check 2: OLS regression present (15 pts) ----
    has_ols = result.get('has_ols', False)
    if has_ols:
        score += 15
        subscores['ols'] = True
        feedback_parts.append("OLS regression results found")
    else:
        subscores['ols'] = False
        feedback_parts.append("OLS regression not found in output")

    # ---- Check 3: RESET test present (20 pts) ----
    has_reset = result.get('has_reset', False)
    if has_reset:
        score += 20
        subscores['reset'] = True
        feedback_parts.append("RESET specification test found")
    else:
        subscores['reset'] = False
        feedback_parts.append("RESET test not found — run Tests > RESET after OLS")

    # ---- Check 4: Breusch-Pagan test (20 pts) ----
    has_bp = result.get('has_bp', False)
    if has_bp:
        score += 20
        subscores['breusch_pagan'] = True
        feedback_parts.append("Breusch-Pagan heteroskedasticity test found")
    else:
        subscores['breusch_pagan'] = False
        feedback_parts.append("Breusch-Pagan test not found")

    # ---- Check 5: White test (20 pts) ----
    has_white = result.get('has_white', False)
    if has_white:
        score += 20
        subscores['white'] = True
        feedback_parts.append("White heteroskedasticity test found")
    else:
        subscores['white'] = False
        feedback_parts.append("White test not found")

    # ---- Check 6: File substantiality (10 pts) ----
    file_size = result.get('file_size', 0)
    if file_size > 5000:
        score += 10
        subscores['substantive'] = True
        feedback_parts.append(f"Output is comprehensive ({file_size} bytes)")
    elif file_size > 2000:
        score += 5
        subscores['substantive'] = 'partial'
        feedback_parts.append(f"Output modest size ({file_size} bytes)")
    else:
        subscores['substantive'] = False
        feedback_parts.append(f"Output too small ({file_size} bytes) for 4+ tests")

    # ---- Independent re-analysis ----
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp2.close()
    try:
        copy_from_env(expected_output, tmp2.name)
        with open(tmp2.name, 'r', errors='replace') as f:
            content = f.read().lower()

        if not has_reset:
            if any(kw in content for kw in ['reset', 'ramsey', 'specification']):
                score = min(100, score + 10)
                feedback_parts.append("RESET confirmed in re-analysis")

        if not has_bp:
            if any(kw in content for kw in ['breusch', 'pagan', 'bp test', 'lm test']):
                score = min(100, score + 10)
                feedback_parts.append("Breusch-Pagan confirmed in re-analysis")

        if not has_white:
            if any(kw in content for kw in ["white's test", "white test", "white hetero"]):
                score = min(100, score + 10)
                feedback_parts.append("White test confirmed in re-analysis")

    except Exception as e:
        logger.info(f"Independent re-analysis skipped: {e}")
    finally:
        if os.path.exists(tmp2.name):
            os.unlink(tmp2.name)

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
