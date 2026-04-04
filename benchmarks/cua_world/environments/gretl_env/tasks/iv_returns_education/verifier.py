#!/usr/bin/env python3
"""Verifier for iv_returns_education task.

The agent must investigate returns to education via IV/2SLS estimation in Gretl
using the Mroz (1987) dataset. This requires:
1. OLS baseline regression (lwage ~ educ + exper + expersq)
2. 2SLS/IV regression (using fatheduc, motheduc as instruments for educ)
3. Hausman endogeneity test
4. Saving all results to /home/ga/Documents/gretl_output/iv_wage_results.txt

Scoring breakdown (100 points total):
- File exists and was created after task start: 15 points
- OLS results present in output: 20 points
- IV/2SLS results present in output: 25 points
- Hausman endogeneity test present: 25 points
- File is substantive (>3KB for multiple models): 15 points

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_iv_returns_education(traj, env_info, task_info):
    """Verify IV/2SLS estimation of returns to education.

    Checks that the agent ran OLS, 2SLS, and Hausman test and saved results.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available"
        }

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/Documents/gretl_output/iv_wage_results.txt')

    # Copy result JSON from VM
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/iv_returns_education_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- Check 1: File exists and was created after task start (15 pts) ----
    file_exists = result.get('file_exists', False)
    created_after = result.get('file_created_after_start', False)

    if file_exists and created_after:
        score += 15
        subscores['file_new'] = True
        feedback_parts.append("Output file created during task")
    elif file_exists and not created_after:
        score += 5
        subscores['file_new'] = False
        feedback_parts.append("Output file exists but predates task start — may be stale")
    else:
        subscores['file_new'] = False
        feedback_parts.append(f"Output file not found at {expected_output}")
        # Can't score further without file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    # ---- Check 2: OLS results present (20 pts) ----
    has_ols = result.get('has_ols', False)
    if has_ols:
        score += 20
        subscores['ols_present'] = True
        feedback_parts.append("OLS baseline results found")
    else:
        subscores['ols_present'] = False
        feedback_parts.append("OLS results not found in output")

    # ---- Check 3: 2SLS/IV results present (25 pts) ----
    has_2sls = result.get('has_2sls', False)
    if has_2sls:
        score += 25
        subscores['iv_present'] = True
        feedback_parts.append("IV/2SLS estimation results found")
    else:
        subscores['iv_present'] = False
        feedback_parts.append("IV/2SLS results not found — check for '2SLS', 'TSLS', or 'Two-Stage'")

    # ---- Check 4: Hausman endogeneity test (25 pts) ----
    has_hausman = result.get('has_hausman', False)
    if has_hausman:
        score += 25
        subscores['hausman_present'] = True
        feedback_parts.append("Hausman endogeneity test found")
    else:
        subscores['hausman_present'] = False
        feedback_parts.append("Hausman test not found — test for endogeneity of educ")

    # ---- Check 5: File substantiality (15 pts) ----
    file_size = result.get('file_size', 0)
    if file_size > 5000:
        score += 15
        subscores['substantive'] = True
        feedback_parts.append(f"File is substantive ({file_size} bytes)")
    elif file_size > 2000:
        score += 8
        subscores['substantive'] = 'partial'
        feedback_parts.append(f"File present but small ({file_size} bytes); expected multiple model outputs")
    else:
        subscores['substantive'] = False
        feedback_parts.append(f"File too small ({file_size} bytes) — likely incomplete output")

    # ---- Independent re-analysis: copy actual file and verify ----
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp2.close()
    try:
        copy_from_env(expected_output, tmp2.name)
        with open(tmp2.name, 'r', errors='replace') as f:
            content = f.read()

        content_lower = content.lower()

        # Cross-verify OLS
        if not has_ols:
            if any(kw in content_lower for kw in ['ols', 'ordinary least squares', 'least squares model']):
                score = min(100, score + 10)
                feedback_parts.append("OLS found in independent re-analysis")

        # Cross-verify 2SLS
        if not has_2sls:
            if any(kw in content_lower for kw in ['2sls', 'tsls', 'two-stage', 'two stage', 'instrumental variables']):
                score = min(100, score + 10)
                feedback_parts.append("2SLS found in independent re-analysis")

        # Cross-verify Hausman
        if not has_hausman:
            if any(kw in content_lower for kw in ['hausman', 'endogeneity', 'wu-hausman']):
                score = min(100, score + 10)
                feedback_parts.append("Hausman test found in independent re-analysis")

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
