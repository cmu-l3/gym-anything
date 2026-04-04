#!/usr/bin/env python3
"""Verifier for var_granger_macro task.

Agent must conduct VAR analysis (lag selection, estimation, Granger causality,
impulse response functions) for inf and i from usa.gdt and save to text file.

Scoring (100 points):
- File exists and was created after task start: 15 points
- VAR/lag order selection evidence: 20 points
- Granger causality test results: 25 points
- Impulse response function results: 25 points
- File substantiality (>4KB): 15 points

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_var_granger_macro(traj, env_info, task_info):
    """Verify VAR analysis with Granger causality and IRFs."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/Documents/gretl_output/var_macro_results.txt')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/var_granger_macro_result.json", tmp.name)
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

    # ---- Check 2: VAR / lag selection present (20 pts) ----
    has_var = result.get('has_var', False)
    has_lag = result.get('has_lag_selection', False)

    if has_var and has_lag:
        score += 20
        subscores['var_lag'] = True
        feedback_parts.append("VAR model and lag selection criteria found")
    elif has_var or has_lag:
        score += 10
        subscores['var_lag'] = 'partial'
        feedback_parts.append("Partial VAR/lag evidence found")
    else:
        subscores['var_lag'] = False
        feedback_parts.append("VAR or lag selection not found in output")

    # ---- Check 3: Granger causality tests (25 pts) ----
    has_granger = result.get('has_granger', False)
    if has_granger:
        score += 25
        subscores['granger'] = True
        feedback_parts.append("Granger causality test results found")
    else:
        subscores['granger'] = False
        feedback_parts.append("Granger causality results not found")

    # ---- Check 4: Impulse response functions (25 pts) ----
    has_irf = result.get('has_irf', False)
    if has_irf:
        score += 25
        subscores['irf'] = True
        feedback_parts.append("Impulse response function results found")
    else:
        subscores['irf'] = False
        feedback_parts.append("Impulse response functions not found")

    # ---- Check 5: File substantiality (15 pts) ----
    file_size = result.get('file_size', 0)
    if file_size > 6000:
        score += 15
        subscores['substantive'] = True
        feedback_parts.append(f"Comprehensive output ({file_size} bytes)")
    elif file_size > 2500:
        score += 8
        subscores['substantive'] = 'partial'
        feedback_parts.append(f"File present but modest size ({file_size} bytes)")
    else:
        subscores['substantive'] = False
        feedback_parts.append(f"File too small ({file_size} bytes) for full VAR output")

    # ---- Independent re-analysis ----
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp2.close()
    try:
        copy_from_env(expected_output, tmp2.name)
        with open(tmp2.name, 'r', errors='replace') as f:
            content = f.read().lower()

        if not has_granger:
            if any(kw in content for kw in ['granger', 'causality', 'wald statistic']):
                score = min(100, score + 10)
                feedback_parts.append("Granger causality confirmed in re-analysis")

        if not has_irf:
            if any(kw in content for kw in ['impulse', 'irf', 'orthogonalized', 'structural shock']):
                score = min(100, score + 10)
                feedback_parts.append("IRF confirmed in re-analysis")

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
