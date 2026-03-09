#!/usr/bin/env python3
"""Verifier for panel_wage_hausman task.

Agent must run Pooled OLS, Fixed Effects, Random Effects, and Hausman test
on the NLS panel wage dataset and save all results to a text file.

Scoring (100 points):
- File exists and was created after task start: 15 points
- Pooled OLS results present: 15 points
- Fixed Effects model results present: 20 points
- Random Effects model results present: 20 points
- Hausman specification test present: 20 points
- File substantiality (>5KB for 4 model outputs): 10 points

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_panel_wage_hausman(traj, env_info, task_info):
    """Verify panel data FE/RE comparison and Hausman test."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/Documents/gretl_output/panel_results.txt')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/panel_wage_hausman_result.json", tmp.name)
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

    # ---- Check 2: Pooled OLS present (15 pts) ----
    has_ols = result.get('has_ols', False)
    if has_ols:
        score += 15
        subscores['pooled_ols'] = True
        feedback_parts.append("Pooled OLS results found")
    else:
        subscores['pooled_ols'] = False
        feedback_parts.append("Pooled OLS results not found")

    # ---- Check 3: Fixed Effects present (20 pts) ----
    has_fe = result.get('has_fe', False)
    if has_fe:
        score += 20
        subscores['fixed_effects'] = True
        feedback_parts.append("Fixed Effects model results found")
    else:
        subscores['fixed_effects'] = False
        feedback_parts.append("Fixed Effects results not found — use Model > Panel > Fixed effects")

    # ---- Check 4: Random Effects present (20 pts) ----
    has_re = result.get('has_re', False)
    if has_re:
        score += 20
        subscores['random_effects'] = True
        feedback_parts.append("Random Effects model results found")
    else:
        subscores['random_effects'] = False
        feedback_parts.append("Random Effects results not found — use Model > Panel > Random effects")

    # ---- Check 5: Hausman test present (20 pts) ----
    has_hausman = result.get('has_hausman', False)
    if has_hausman:
        score += 20
        subscores['hausman'] = True
        feedback_parts.append("Hausman specification test found")
    else:
        subscores['hausman'] = False
        feedback_parts.append("Hausman test not found — run from Tests menu after RE model")

    # ---- Check 6: File substantiality (10 pts) ----
    file_size = result.get('file_size', 0)
    if file_size > 6000:
        score += 10
        subscores['substantive'] = True
        feedback_parts.append(f"Comprehensive output ({file_size} bytes)")
    elif file_size > 2500:
        score += 5
        subscores['substantive'] = 'partial'
        feedback_parts.append(f"Output modest size ({file_size} bytes)")
    else:
        subscores['substantive'] = False
        feedback_parts.append(f"Output too small ({file_size} bytes) for 4 models")

    # ---- Independent re-analysis ----
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp2.close()
    try:
        copy_from_env(expected_output, tmp2.name)
        with open(tmp2.name, 'r', errors='replace') as f:
            content = f.read().lower()

        if not has_fe:
            if any(kw in content for kw in ['fixed effect', 'within model', 'fe estimator']):
                score = min(100, score + 10)
                feedback_parts.append("Fixed Effects confirmed in re-analysis")

        if not has_re:
            if any(kw in content for kw in ['random effect', 'gls', 'egls', 're estimator']):
                score = min(100, score + 10)
                feedback_parts.append("Random Effects confirmed in re-analysis")

        if not has_hausman:
            if any(kw in content for kw in ['hausman', 'specification test']):
                score = min(100, score + 10)
                feedback_parts.append("Hausman test confirmed in re-analysis")

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
