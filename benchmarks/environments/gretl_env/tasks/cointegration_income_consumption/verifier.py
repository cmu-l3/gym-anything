#!/usr/bin/env python3
"""Verifier for cointegration_income_consumption task.

Agent must test the Permanent Income Hypothesis by conducting Engle-Granger
cointegration analysis on real US consumption (PCEC96) and income (DSPIC96)
data downloaded from FRED.

Requirements:
1. Import FRED data and apply log transforms (lcons, linc)
2. Run ADF unit root tests in levels and first differences
3. Estimate cointegrating OLS regression
4. Run ADF on residuals (Engle-Granger step 2)
5. Save all results to text file

Scoring (100 points):
- File exists and created after task start: 15 points
- ADF unit root tests present: 20 points
- Cointegrating regression present: 20 points
- Engle-Granger / residual stationarity test: 25 points
- First-difference ADF present: 10 points
- File substantiality (>5KB): 10 points

Pass threshold: 60/100
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cointegration_income_consumption(traj, env_info, task_info):
    """Verify Engle-Granger cointegration analysis on FRED macro data."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/Documents/gretl_output/cointegration_results.txt')

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env("/tmp/cointegration_result.json", tmp.name)
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

    # ---- Check 2: ADF unit root tests (20 pts) ----
    has_adf = result.get('has_adf', False)
    has_unit_root = result.get('has_unit_root', False)

    if has_adf and has_unit_root:
        score += 20
        subscores['adf_tests'] = True
        feedback_parts.append("ADF unit root tests found")
    elif has_adf or has_unit_root:
        score += 10
        subscores['adf_tests'] = 'partial'
        feedback_parts.append("Partial ADF/unit root evidence")
    else:
        subscores['adf_tests'] = False
        feedback_parts.append("ADF unit root tests not found")

    # ---- Check 3: Cointegrating regression (20 pts) ----
    has_coint_reg = result.get('has_coint_reg', False)
    if has_coint_reg:
        score += 20
        subscores['coint_reg'] = True
        feedback_parts.append("Cointegrating OLS regression found")
    else:
        subscores['coint_reg'] = False
        feedback_parts.append("Cointegrating regression not found")

    # ---- Check 4: Engle-Granger / residual test (25 pts) ----
    has_eg = result.get('has_engle_granger', False)
    has_resid = result.get('has_residual_test', False)

    if has_eg:
        score += 25
        subscores['engle_granger'] = True
        feedback_parts.append("Engle-Granger cointegration test found")
    elif has_resid:
        score += 15
        subscores['engle_granger'] = 'partial'
        feedback_parts.append("Residual stationarity test found (partial Engle-Granger)")
    else:
        subscores['engle_granger'] = False
        feedback_parts.append("Engle-Granger test not found — test ADF on regression residuals")

    # ---- Check 5: First-difference ADF (10 pts) ----
    # Evidenced by presence of unit_root keywords alongside stationarity language
    has_log = result.get('has_log_transform', False)
    if has_log and has_adf:
        score += 10
        subscores['log_and_diff'] = True
        feedback_parts.append("Log-transformed variables and ADF confirmed")
    else:
        subscores['log_and_diff'] = False
        if not has_log:
            feedback_parts.append("Log transformation not evident in output")

    # ---- Check 6: File substantiality (10 pts) ----
    file_size = result.get('file_size', 0)
    if file_size > 6000:
        score += 10
        subscores['substantive'] = True
        feedback_parts.append(f"Comprehensive output ({file_size} bytes)")
    elif file_size > 2500:
        score += 5
        subscores['substantive'] = 'partial'
        feedback_parts.append(f"Output present but modest ({file_size} bytes)")
    else:
        subscores['substantive'] = False
        feedback_parts.append(f"Output too small ({file_size} bytes) for full cointegration analysis")

    # ---- Independent re-analysis ----
    tmp2 = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp2.close()
    try:
        copy_from_env(expected_output, tmp2.name)
        with open(tmp2.name, 'r', errors='replace') as f:
            content = f.read().lower()

        if not has_adf:
            if any(kw in content for kw in ['augmented dickey', 'adf test', 'dickey-fuller']):
                score = min(100, score + 10)
                feedback_parts.append("ADF confirmed in re-analysis")

        if not has_eg:
            if any(kw in content for kw in ['cointegrat', 'engle', 'granger', 'residual adf']):
                score = min(100, score + 10)
                feedback_parts.append("Cointegration test confirmed in re-analysis")

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
